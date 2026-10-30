#!/bin/sh
# A pool name alone must never authorize native/destructive tests.
set -eu
cd "$(dirname "$0")/.."
if [ ! -f tests/native-common.sh ]; then
    echo 'FAIL: native tests have no shared destructive opt-in guard'
    exit 1
fi
. ./tests/native-common.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-native-guard.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
uname () { echo "$test_os"; }
id () { echo "$test_uid"; }
zfs () {
    echo "zfs $*" >> "$trace"
    [ "$property_error" = no ] || return 42
    [ "$1" = get ] || return 99
    echo "$marker"
}
df () {
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n'
    printf '%s 100 1 99 1%% /iocell\n' "$mounted_dataset"
}
uclcmd () { echo "$selected_pool"; }
failed=0
for label in opt-in missing-pool platform credentials unmarked query wrong-mount wrong-selection accepted; do
    trace="$workdir/$label.trace"; : > "$trace"
    test_os=FreeBSD; test_uid=0; marker=yes; property_error=no
    mounted_dataset=tank/iocell; selected_pool=tank
    IOC_TEST_DESTRUCTIVE=yes; IOC_TEST_POOL=tank; want=1
    case "$label" in
        opt-in) unset IOC_TEST_DESTRUCTIVE ;;
        missing-pool) unset IOC_TEST_POOL ;;
        platform) test_os=Linux ;;
        credentials) test_uid=1000 ;;
        unmarked) marker=- ;;
        query) property_error=yes ;;
        wrong-mount) mounted_dataset=production/iocell ;;
        wrong-selection) selected_pool=production ;;
        accepted) want=0 ;;
    esac
    status=0
    ( ioc_test_require_pool ) > "$workdir/$label.out" 2> "$workdir/$label.err" || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: native guard $label returned $status, expected $want"
        failed=1; continue
    fi
    if [ "$want" = 1 ] && [ ! -s "$workdir/$label.err" ]; then
        echo "FAIL: native guard $label has no diagnostic"; failed=1; continue
    fi
    case "$label" in
        opt-in|missing-pool|platform|credentials)
            [ ! -s "$trace" ] || { echo "FAIL: $label probed a pool"; failed=1; continue; } ;;
    esac
    echo "PASS: native guard $label"
done
exit "$failed"
