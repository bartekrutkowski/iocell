#!/bin/sh
# Remove only managed send snapshots, never user snapshots or clone datasets.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-send-cleanup.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank
zfs () {
    case "$1" in
        list)
            [ "$fault" != query ] || return 8
            printf '%s\n' tank/iocell@ioc-send-old \
                tank/iocell/jails/fixture/root@ioc-send-old \
                tank/iocell/releases/test/root@ioc-send-old \
                tank/iocell@ioc-send-current \
                tank/iocell@user-ioc-note tank/iocell@ioc-clone-keep \
                tank/iocell/other@prefix-ioc-send-user \
                tank/other@ioc-send-keep
            ;;
        destroy)
            printf '%s\n' "$*" >> "$state/trace"
            if [ "$fault" = clone ]; then
                case " $* " in *' -rR '*|*' -R '*) rm "$state/clone" ;; *) return 9 ;; esac
            fi
            for last; do :; done
            case "$last" in
                tank/iocell@ioc-send-old) rm -f "$state/managed-root" ;;
                tank/iocell/jails/fixture/root@ioc-send-old) rm -f "$state/managed-child" ;;
                tank/iocell/releases/test/root@ioc-send-old) rm -f "$state/release" ;;
                tank/iocell@ioc-send-current) rm -f "$state/current" ;;
                *) rm -f "$state/unrelated" ;;
            esac ;;
    esac
}
failed=0
for fault in none query clone jails keep; do
    state="$workdir/$fault"; mkdir "$state"
    for file in managed-root managed-child unrelated clone release current; do echo preserved > "$state/$file"; done
    : > "$state/trace"; status=0
    args=''
    case "$fault" in jails) args=tank/iocell/jails ;; keep) args='tank/iocell ioc-send-current' ;; esac
    ( __clean_snapshots $args ) > "$state/log" 2>&1 || status=$?
    want=0; case "$fault" in query) want=8 ;; clone) want=9 ;; esac
    if [ "$status" != "$want" ] || [ ! -e "$state/unrelated" ] || [ ! -e "$state/clone" ]; then
        echo "FAIL: send cleanup $fault lost unrelated data or masked status=$status"; failed=1; continue
    fi
    case "$fault" in
        jails)
            if [ -e "$state/managed-child" ] || [ ! -e "$state/managed-root" ] ||
                [ ! -e "$state/release" ] || [ ! -e "$state/current" ]; then
                echo 'FAIL: jail cleanup modified points outside jails'; failed=1; continue
            fi ;;
        keep)
            if [ ! -e "$state/current" ] || [ -e "$state/managed-root" ] ||
                [ -e "$state/managed-child" ] || [ -e "$state/release" ]; then
                echo 'FAIL: cleanup lost its replication base or kept older managed points'; failed=1; continue
            fi ;;
        none)
            if [ -e "$state/release" ] || [ -e "$state/current" ] ||
                [ -e "$state/managed-root" ] || [ -e "$state/managed-child" ]; then
                echo 'FAIL: managed snapshots were not removed'; failed=1; continue
            fi ;;
        query|clone)
            [ -e "$state/managed-root" ] && [ -e "$state/managed-child" ] || {
                echo "FAIL: send cleanup $fault changed snapshots"; failed=1; continue;
            } ;;
    esac
    if grep -E -- '-[^ ]*R' "$state/trace" >/dev/null; then
        echo 'FAIL: cleanup disabled native clone protection'; failed=1; continue
    fi
    echo "PASS: send cleanup $fault"
done
exit "$failed"
