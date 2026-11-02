#!/bin/sh
# Failed ALL enumeration must stop real consumers, even with partial stdout.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-help
. ./lib/ioc-rctl
. ./lib/ioc-network
. ./lib/ioc-configure
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-discovery-callers.XXXXXX")
trap 'if [ "$failed" = 0 ]; then rm -rf "$workdir"; else echo "Retained: $workdir"; fi' EXIT
pool=tank; uuid=11111111-1111-1111-1111-111111111111
fixture_uuid="$uuid"
ds="tank/iocell/jails/$uuid"
iocroot="$workdir/tree"; mkdir -p "$iocroot/releases/15.1-RELEASE"
__find_jail () {
    if [ "$1" = ALL ]; then
        printf '%s\n' "$ds" tank/iocell/templates/template
        if [ "$fault" = yes ]; then
            echo failed > "$state/failed"
            echo 'fixture discovery query failure' >&2
            return 42
        fi
    else echo "$ds"; fi
}
__check_name () { echo "$fixture_uuid"; }
__get_jail_prop () {
    [ ! -f "$state/failed" ] || echo "read $1" >> "$trace"
    case "$1" in
        type) echo basejail ;; release) echo 15.1-RELEASE ;;
        mountpoint) echo "$iocroot/jails/$uuid" ;; tag) echo fixture ;;
        ip4_autostart) echo 10 ;; ip4_autoend) echo 20 ;; ip4_autosubnet) echo 24 ;;
        ip4_addr) echo none ;; *) echo 0 ;;
    esac
}
__is_running () { :; }
__set_jail_prop () { echo set >> "$trace"; }
__reset_jail_props () {
    echo reset >> "$trace"
    [ "$#" = 1 ] && [ "$1" = "$uuid" ] || return 76
}
jls () { [ "$*" != '-N -h jid' ] || echo jid; }
uname () { echo 15.1-RELEASE; }
netstat () { echo 'default 192.0.2.1'; }
rctl () { echo rctl >> "$trace"; }
zfs () { echo "zfs $*" >> "$trace"; echo 0; }
column () { cat; }
failed=0
for label in list templates warden warden-dispatch rctl rctl-dispatch autoip reset show disk; do
    for fault in yes no; do
        state="$workdir/$label-$fault"; mkdir "$state"
        trace="$state/trace"; : > "$trace"; status=0; want=0
        [ "$fault" != yes ] || want=42
        (
            set +e
            case "$label" in
                list) __list_jails '' ;; templates) __list_jails -t ;;
                warden) __list_jails_warden ;;
                warden-dispatch) __list_jails --warden ;; rctl) __rctl_inuse_all ;;
                rctl-dispatch) __rctl_inuse '' ;;
                autoip) __get_autoip4 ;;
                reset) __reset_jail_props_all ;; show) __show notes ;;
                disk) __print_disk ;;
            esac
        ) > "$state/out" 2> "$state/err" || status=$?
        if [ "$status" != "$want" ]; then
            echo "FAIL: discovery consumer $label/$fault status=$status expected=$want"
            failed=1; continue
        fi
        if [ "$fault" = yes ] && [ -s "$trace" ]; then
            echo "FAIL: discovery consumer $label continued after failed enumeration"
            failed=1; continue
        fi
        if [ "$fault" = no ]; then
            case "$label" in
                show|disk|list) grep -q "$uuid" "$state/out" || { failed=1; continue; } ;;
                templates|warden|warden-dispatch) grep -q fixture "$state/out" || { failed=1; continue; } ;;
                reset) grep -qx reset "$trace" || { failed=1; continue; } ;;
            esac
        fi
        echo "PASS: discovery consumer $label/$fault"
    done
done
# The reset entrypoint enumerates once before confirmation and again for work.
# Its outer dispatcher must preserve the second enumeration/child failure too.
for fault in yes no; do
    state="$workdir/reset-public-$fault"; mkdir "$state"
    trace="$state/trace"; : > "$trace"; echo 0 > "$state/count"
    status=0; want=42; [ "$fault" != no ] || want=73
    (
        set +e
        . ./lib/ioc-configure
        __find_jail () {
            if [ "$1" = ALL ]; then
                n=$(cat "$state/count"); n=$((n+1)); echo "$n" > "$state/count"
                echo "$ds"
                if [ "$n" = 2 ] && [ "$fault" = yes ]; then return 42; fi
            else echo "$ds"; fi
        }
        __configure_jail () { echo configure >> "$trace"; return 73; }
        printf 'y\n' | __reset_jail_props ALL
    ) > "$state/out" 2> "$state/err" || status=$?
    if [ "$status" != "$want" ] ||
        { [ "$fault" = yes ] && [ -s "$trace" ]; }; then
        echo "FAIL: reset dispatcher masked discovery/child failure $fault ($status)"; failed=1
    else echo "PASS: reset dispatcher preserves discovery/child failure $fault"; fi
done
exit "$failed"
