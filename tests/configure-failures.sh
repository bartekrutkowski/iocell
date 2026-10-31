#!/bin/sh
# Real configuration generation/UCL helper, with an external parser boundary.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-configure
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-configure.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
CONF_NET=''; CONF_JAIL=''; CONF_RCTL=''; CONF_CUSTOM='notes owner'
CONF_SYNC=''; CONF_FTP=''; CONF_GIT=''; CONF_ZFS=''
notes=new-notes; owner=new-owner
uuid=11111111-1111-1111-1111-111111111111
pool=tank; ds="tank/iocell/jails/$uuid"
__get_jail_prop () { [ "$1" = mountpoint ] || return 99; echo "$mp"; }
zfs () {
    echo "zfs $*" >> "$trace"
    if [ "$mode" = altroot ]; then
        [ "$*" = "set compression=lz4 $ds" ] || return 99
    else return 43; fi
}
uclcmd () {
    input=''; output=''; shift
    while [ "$#" -gt 0 ]; do
        case "$1" in -f|-qf) input=$2; shift 2 ;; -o) output=$2; shift 2 ;;
            -t) shift 2 ;; --) shift; break ;; -*) shift ;; *) break ;; esac
    done
    echo "$1" >> "$trace"
    [ "$mode" != generate-failure ] && [ "$mode" != reset-failure ] || return 42
    [ -n "$output" ] || output="$input"
    awk -F= -v key="$1" '$1!=key' "$input" > "$input.fake"
    printf '%s=%s\n' "$1" "$2" >> "$input.fake"
    mv "$input.fake" "$output"
}
failed=0
for mode in generate-failure reset-failure native-failure success altroot; do
    mp="$workdir/$mode"; iocroot="$workdir"
    if [ "$mode" = altroot ]; then
        iocroot="$workdir/altroot/iocell"; mp="$iocroot/jails/$uuid"
    fi
    mkdir -p "$mp"
    trace="$mp/actions"; : > "$trace"; CONF_ZFS=''; want=42
    printf 'notes=old\nowner=old\n' > "$mp/config"; cp "$mp/config" "$mp/before"
    case "$mode" in native-failure) CONF_ZFS='compression quota'; compression=lz4; quota=none; want=43 ;;
        success) want=0 ;;
        altroot) CONF_ZFS=compression; compression=lz4; want=0 ;; esac
    status=0
    (
        if [ "$mode" = reset-failure ]; then __configure_jail "$uuid" "$ds"
        elif [ "$mode" = altroot ]; then __configure_jail generate "$uuid"
        else __configure_jail generate "$uuid" "$ds" "$mp"; fi
    ) > "$mp/log" 2>&1 || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: config $mode status=$status expected=$want"; failed=1; continue
    fi
    case "$mode" in
        *-failure)
            if [ "$mode" != native-failure ]; then
                cmp "$mp/config" "$mp/before" || exit 1
                printf 'notes\n' > "$mp/expected"
                cmp "$trace" "$mp/expected" || exit 1
            else
                printf 'notes\nowner\nzfs set compression=lz4 %s\n' "$ds" > "$mp/expected"
                if ! cmp -s "$trace" "$mp/expected"; then
                    echo 'FAIL: config continued native writes after failure'; failed=1
                fi
            fi ;;
        success|altroot) grep -qx 'notes=new-notes' "$mp/config"; grep -qx 'owner=new-owner' "$mp/config" ;;
    esac
    echo "PASS: config generation $mode"
done
exit "$failed"
