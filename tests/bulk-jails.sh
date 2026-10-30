#!/bin/sh
# Bulk operations must report a failed/unconfigured jail and still reach others.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-rc
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-bulk.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; iocroot="$workdir/iocell"
first=11111111-1111-1111-1111-111111111111
second=22222222-2222-2222-2222-222222222222
for uuid in "$first" "$second"; do
    mkdir -p "$iocroot/jails/$uuid"
    echo config > "$iocroot/jails/$uuid/config"
done
__find_jail () {
    printf '%s\n' "tank/iocell/jails/$first" "tank/iocell/jails/$second"
    [ "$mode" != query ] || return 9
}
__check_name () { echo "${2##*/}"; }
__get_jail_prop () { echo fixture; }
__is_running () { [ "$action" = start ] || echo 1; }
zfs () { for arg in "$@"; do :; done; echo "$iocroot/jails/${arg##*/}"; }
uclcmd () {
    [ -f "$3" ] || return 1
    parent="${3%/config}"
    echo "${parent##*/}"
}
operation () {
    echo "$1" >> "$trace"
    if [ "$mode" = backend ] && [ "$1" = "$first" ]; then
        __die 'fixture backend failure'
    fi
}
__start_jail () { operation "$1"; }
__stop_jail () { operation "$1"; }
__reboot_jail () { operation "$1"; }
__restart_jail () { operation "$1"; }
failed=0
for action in start stop reboot restart; do
    for mode in backend unconfigured query; do
        trace="$workdir/$action-$mode.trace"; : > "$trace"
        echo config > "$iocroot/jails/$first/config"
        [ "$mode" != unconfigured ] || rm "$iocroot/jails/$first/config"
        status=0
        ( "__${action}_jail_all" ) > "$workdir/$action-$mode.log" 2>&1 || status=$?
        want=1
        [ "$mode" != query ] || want=9
        if [ "$status" != "$want" ]; then
            echo "FAIL: bulk $action $mode status=$status, expected $want"; failed=1; continue
        fi
        if [ "$mode" = query ]; then
            [ ! -s "$trace" ] || { echo 'FAIL: truncated discovery was executed'; failed=1; continue; }
        else
            grep -Fx "$second" "$trace" >/dev/null || {
                echo "FAIL: bulk $action $mode skipped the later jail"; failed=1; continue;
            }
            if [ "$mode" = unconfigured ] && grep -Fx "$first" "$trace" >/dev/null; then
                echo "FAIL: bulk $action used missing configuration"; failed=1; continue
            fi
        fi
        echo "PASS: bulk $action $mode"
    done
done
exit "$failed"
