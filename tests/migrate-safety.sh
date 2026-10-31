#!/bin/sh
# Legacy migration must reject bad conversion targets before destruction and
# reap its spinner even when a nested backend returns or exits with failure.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-migrate.XXXXXX")
cleanup () {
    for file in "$workdir"/*/pid; do
        [ -f "$file" ] || continue
        while read -r pid; do command kill "$pid" 2>/dev/null || :; done < "$file"
    done
    rm -rf "$workdir"
}
trap cleanup EXIT
pool=tank; uuid=11111111-1111-1111-1111-111111111111
basedirs=bin
__get_jail_prop () {
    case "$1" in
        template) echo yes ;;
        tag) echo "$fixture_tag" ;;
        mountpoint) echo "$parent" ;;
    esac
}
__check_children () { return 0; }
__ucl_set () { :; }
__set_jail_prop () {
    [ "$1" = istemplate=yes ] || return 0
    case "$mode" in
        backend-return) __error 'fixture conversion return'; return 9 ;;
        backend-exit) __die 'fixture conversion exit' ;;
    esac
}
zfs () {
    case "$1" in
        get) [ "$mode" = destination ] ;;
        destroy)
            jobs -p > "$state/pid"
            echo "destroy $*" >> "$state/trace"
            ;;
    esac
}
failed=0
for mode in unsafe-tag destination backend-return backend-exit success; do
    state="$workdir/$mode"; iocroot="$state/iocell"
    parent="$iocroot/jails/$uuid"
    mkdir -p "$parent/root/usr/local" "$parent/root/usr/home" \
        "$iocroot/releases/15.1-RELEASE/root/etcupdate"
    echo local > "$parent/root/usr/local/marker"
    echo home > "$parent/root/usr/home/marker"
    : > "$state/trace"
    fixture_tag=migration-template; want=1
    case "$mode" in unsafe-tag) fixture_tag='2026-01-01@00:00:00' ;;
        backend-return) want=9 ;; success) want=0 ;; esac
    status=0
    ( __migrate_basejail "$uuid" 15.1-RELEASE ) > "$state/log" 2>&1 || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: migration $mode status=$status expected=$want"; failed=1
    elif [ "$mode" = unsafe-tag ] || [ "$mode" = destination ]; then
        if [ -s "$state/trace" ]; then
            echo "FAIL: migration $mode destroyed datasets before target preflight"; failed=1
        else echo "PASS: migration $mode preflight"; fi
    else
        if [ ! -s "$state/pid" ]; then
            echo "FAIL: migration $mode did not exercise a running spinner"; failed=1
        else
            while read -r pid; do
                if command kill -0 "$pid" 2>/dev/null; then
                    echo "FAIL: migration $mode left spinner $pid alive"; failed=1
                else echo "PASS: migration $mode reaps spinner"; fi
            done < "$state/pid"
        fi
    fi
    [ "$(cat "$parent/root/usr/local/marker")" = local ] || exit 1
    [ "$(cat "$parent/root/usr/home/marker")" = home ] || exit 1
done
exit "$failed"
