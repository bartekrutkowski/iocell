#!/bin/sh
# Returned and exiting failures must survive dispatch and stop later deletion.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-cmd
. ./lib/ioc-zfs
. ./tests/cli-dispatch.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-destroy-status.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; ds=tank/iocell/jails/fixture
failed=0
for mode in returned exiting success; do
    trace="$workdir/$mode.trace"; : > "$trace"; status=0
    (
        __destroy_jail () {
            printf '%s:%s\n' "$1" "$_force" >> "$trace"
            [ "$1" != first ] || [ "$mode" = success ] || {
                if [ "$mode" = exiting ]; then exit 42; else return 42; fi
            }
        }
        ioc_test_dispatch destroy -f first second
    ) > "$workdir/$mode.log" 2>&1 || status=$?
    want=42; printf 'first:1\n' > "$workdir/expected"
    if [ "$mode" = success ]; then want=0; printf 'second:1\n' >> "$workdir/expected"; fi
    if [ "$status" != "$want" ] || ! cmp -s "$trace" "$workdir/expected"; then
        echo "FAIL: destroy dispatch $mode lost status or continued deleting"; failed=1
    else echo "PASS: destroy dispatch $mode"; fi
done
__unlink_tag () {
    [ "$#" = 2 ] && [ "$2" = "$mp/data" ] || return 99
    echo unlink >> "$trace"; rm -f "$mp/alias"
}
zfs () {
    echo "zfs $*" >> "$trace"
    case "$*" in
        'get -rH -o name,value origin tank')
            [ "$mode" != query ] || return 44
            printf 'tank\t-\n%s\t-\n' "$ds" ;;
        'get -r -H -o value origin tank') echo - ;;
        "destroy -fr $ds")
            [ "$mode" != native ] || return 43
            if [ "$mode" = leftover ]; then rm "$mp/data/canary"
            else rm -rf "$mp/data"; fi ;;
        *) echo "unexpected zfs: $*" >&2; return 99 ;;
    esac
}
for mode in native query success leftover; do
    mp="$workdir/backend-$mode"; mkdir -p "$mp/data"
    echo keep > "$mp/data/canary"; touch "$mp/alias"
    [ "$mode" != leftover ] || echo host-data > "$mp/data/host-file"
    trace="$workdir/backend-$mode.trace"; : > "$trace"; status=0
    ( __destroy_func fixture "$ds" - basejail "$mp/data" ) > "$mp/log" 2>&1 || status=$?
    want=0; case "$mode" in native) want=43 ;; query) want=44 ;; leftover) want=1 ;; esac
    if [ "$status" != "$want" ]; then
        echo "FAIL: destroy backend $mode status=$status expected=$want"; failed=1; continue
    fi
    if [ "$mode" = leftover ]; then
        [ "$(cat "$mp/data/host-file")" = host-data ] || exit 1
    elif [ "$mode" != success ]; then
        if [ "$(cat "$mp/data/canary")" != keep ] || [ ! -f "$mp/alias" ]; then
            echo "FAIL: destroy backend $mode deleted data or aliases after failure"; failed=1; continue
        fi
    else [ ! -e "$mp/data" ] && [ ! -e "$mp/alias" ] || exit 1; fi
    echo "PASS: destroy backend $mode"
done
exit "$failed"
