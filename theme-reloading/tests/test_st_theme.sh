set -e
here="$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd)"
export PATH="$(cd $here/../; pwd):$PATH"
export cur_test=
export d_test_work="$here/work"
tests=
d_tmp="$d_test_work/tmp/st"
d_cfg="$d_test_work/config/st_theme"
# allows to insert /bin/bash within tests and run the same:
export STT="st_theme -D $d_cfg"
export WINDOWID=1233456

tmsg () { echo -e "$*"; }

# ------------------------------------------------------------------------------- mocks
fzf_args=
fzf_out=

kill () {
    local fn="$d_test_work/kill_args"
    [ "$1" == args ] && { cat "$fn"; return; }
    echo "$*" > "$fn"
}

xdotool () {
    local fn="$d_test_work/xdotool_args"
    echo "$*" > "$fn"
    test "$1" == selectwindow && echo "selected_otherwid"
    return 0
}

fzf () {
    fzf_callback "$*"
}

export -f kill
export -f fzf
export -f xdotool

function cleanup {
    rm -rf "$d_test_work"
    mkdir -p "$d_test_work"
    if [ "$1" == and_add_test_schemes ]; then
        mkdir -p "$d_test_work/dl/base16"
        cp -a "$here/assets/schemes" "$d_test_work/dl/base16"
        clean_config
    fi
}

function clean_config {
    rm -rf "$d_cfg"
    rm -rf "${d_tmp:?}"/*
    mkdir -p "$d_cfg"
    echo "ST_THEMES_DIR='$d_test_work/dl/base16/output/st_theme'" > "$d_cfg/config.sh"
    echo "d_tmp='$d_tmp'" >> "$d_cfg/config.sh"
}

function die {
    echo -e "\x1b[38;5;124m$cur_test failed\x1b[0m"
    echo -e "$1"; shift
    test "$1" && echo -e "Details:\n$*"
    exit 1
}

function has {
    fn="$1"; test -e "$fn" || fn="$d_tmp/mywid/$fn"
    shift
    for v in "$@"; do
        sed -e "s/\ //g" < "$fn" | grep "$v" || die "Expected but not found:\n$v in $fn" 
    done
}
function eql {
    local content
    fn="$1"; test -e "$fn" || fn="$d_tmp/mywid/$fn"
    # we strip all spaces, format of xrdb file too prone to failure otherwise
    content="$(sed -e "s/\ //g" "$fn" | sed -e '/^$/d' )"
    test "$content" == "$(echo -e "$2")" || die "$fn: Content not equal:\n$*" "is:\n$content"
}

# -------------------------------------------------------------------------------------
# ------------------ TESTS ------------------------------------------------------------
# -------------------------------------------------------------------------------------

function test_b16fetch {
    export test_max_downloads="..."
    d="$d_test_work/dl"
    mkdir -p "$d"
    cd "$d"
    $STT b16fetch
    find . -print |grep schemes | grep yaml
}

function test_b16convert {
    cleanup and_add_test_schemes
    cd "$d_test_work/dl"
    $STT b16convert -y 
    source "$d_cfg/config.sh"
    test "$(ls "$ST_THEMES_DIR/"*.config | head -n 3 | wc -l)" == "3"
}

function test_list {
    tmsg "Checking for Atelier Cave Light"
    $STT list -P | grep '\[48;2;87;109;219m' | grep 'Atelier Cave Light' | grep -v 'atelier-cave'
}

function test_set[empty_config]:alpha {
    clean_config
    $STT set -w mywid -p mypid -c alpha=0.1
    eql config "alpha=0.1"
    eql "xrdb" '*alpha:0.1'
    eql "pid" 'mypid'
    eql "$d_test_work/kill_args" "-1mypid"
}

function test_set[empty_config]:alpha_rel {
    clean_config
    $STT set -w mywid -p mypid -a '-0.1'
    eql config "alpha=0.9"
    eql "xrdb" '*alpha:0.9'
    eql "pid" 'mypid'
    eql "$d_test_work/kill_args" "-1mypid"
}

function test_set[empty_config]:theme {
    clean_config
    $STT set -w mywid -p mypid -t 'atlas' -a 0.1
    eql config "alpha=1.1\ntheme=atlas"
    eql "pid" 'mypid'
    has  "$d_tmp/mywid/xrdb" '*alpha:1.1' '*color0:#002635'
    eql "$d_test_work/kill_args" "-1mypid"
}

function test_set[empty_config]:theme_and_custom_overwrites {
    clean_config
    $STT set -w mywid -p mypid -t 'atlas' -c background="#FF0000"
    eql config "alpha=1\ntheme=atlas\nbackground=#FF0000"
    has xrdb '*alpha:1' '*background:#FF0000' '*foreground:#a1a19a'
}

function test_set[empty_config]:no_theme_source_at_subseq_customization {
    clean_config
    $STT set -w mywid -p mypid -t 'atlas' -c background="#FF0000"
    # Another customization no theme change:
    $STT set -w mywid -p mypid -t atlas -c alpha=0.2 -c background="#FF0001"
    eql config "alpha=0.2\ntheme=atlas\nbackground=#FF0001"
    has xrdb '*alpha:0.2' '*background:#FF0001' 
    # since the theme did not change we did NOT write it into xrdb again:
    grep foreground "$d_tmp/mywid/xrdb" && die "Unexpected *foreground w/o theme change"
    return 0
}

function test_set[empty_config]:new_theme_sourced_at_subseq_customization_with_new_theme {
    clean_config
    $STT set -w mywid -p mypid -t 'atlas' -c background="#FF0000"
    # Another customization no theme change:
    $STT set -w mywid -p mypid -t atelier-cave -c alpha=0.2 -c background="#FF0002"
    eql config "alpha=0.2\ntheme=atelier-cave\nbackground=#FF0002"
    # since the theme did change we did write it into xrdb again:
    has xrdb '*alpha:0.2' '*background:#FF0002' '*foreground:#8b8792'
    return 0
}

function test_set[empty_config]:theme_fuzzy_selected_alpha_rel_changes {
    clean_config
    fzf_callback () { echo "atelier-cave"; }
    export -f fzf_callback
    $STT set -w mywid -p mypid -t 'z' -c background="#FF0000"
    eql config "alpha=1\ntheme=atelier-cave\nbackground=#FF0000"
    has xrdb '*alpha:1' '*background:#FF0000' '*foreground:#8b8792'
    # change
    $STT set -w mywid -p mypid -t 'atlas' -a -0.1 -c background="#FF0002"
    has config 'theme=atlas' 'alpha=0.9'
    has xrdb '*foreground' '*foreground:#a1a19a'

    # select again cave:
    $STT set -w mywid -p mypid -t 'a' -a -0.1 -c background="#FF0003"
    eql config "alpha=0.8\ntheme=atelier-cave\nbackground=#FF0003"
    has xrdb '*alpha:0.8' '*background:#FF0003' '*foreground:#8b8792'
}


function test_sel[empty_config]:theme_select {
    clean_config
    fzf_callback () { fzf_on_select '\tatlas\t'; exit 130; }; export -f fzf_callback
    $STT select -w mywid -p mypid
    eql config "alpha=1\ntheme=atlas"
    has xrdb '*foreground' '*foreground:#a1a19a' '*alpha:1'
}

function test_sel[empty_config]:theme_select_revert {
    test_sel[empty_config]:theme_select
    eql config "alpha=1\ntheme=atlas"
    fzf_callback () {
        fzf_on_select '\tatelier-cave\t' &
        cp "$d_tmp/mywid/config" "$d_test_work/config1"
        eql config "alpha=1\ntheme=atelier-cave"
        revert
        cp "$d_tmp/mywid/config" "$d_test_work/config2"
        eql config "alpha=1\ntheme=atlas"
        exit 130
    }; export -f fzf_callback
    $STT select -w mywid -p mypid
    return 0
}


function run {
    tmsg "

-------------------------------------------------------------------------------------------
$1
-------------------------------------------------------------------------------------------
    "
    cur_test="$1"
    $1 "$@" || die 
    success="$success\n$1"
}
function find_tests {
    tests="$(echo -e "$(grep "^function test_" "$0" | cut -d ' ' -f 2 | grep -E "$match" )")"
}

function summary {
    echo -e "
========================================================
Summary
========================================================
    "

    for t in $(echo -e "$success"); do echo -e "\x1b[38;5;156msuccess\x1b[0m: $t"; done
}

usage () {
    echo -e "Tests:\n$tests\n"
    echo "With the -s switch we start clean pulling all base16 schemes -> takes a while"
    echo "has normal mode we copy over a few saved schemes into the workdir"
    echo "-m: add match pattern"
}


function main {
    success=""
    find_tests
    match=test
    skip_slow=true
    while getopts "hm:s" opt; do
        case ${opt} in
            h) usage; exit 0;
                ;;
            m) match="$OPTARG"
                ;;
            s) skip_slow=false
                ;;
        esac
    done
    find_tests
    echo "$tests" | grep -E 'fetch|convert' && cleanup
    for t in $tests
    do
        $skip_slow && test "$t" == test_b16fetch && continue
        run "$t"
    done
    summary
}
main "$@"
