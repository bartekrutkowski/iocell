#!/bin/sh
# Managed snapshot cleanup must retain user points, clone GUIDs and data.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-send-cleanup.XXXXXX)
p=$(ioc_test_pool_name iocsclean)
echo "Retained cleanup logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
zfs create -o mountpoint="$workdir/tree" "$p/iocell"
u=$(uuidgen)
root="$p/iocell/jails/$u/root"
zfs create -p "$root"
zfs create "$p/other"
mp=$(zfs get -H -o value mountpoint "$root")
echo preserved > "$mp/marker"
zfs snapshot -r "$p/iocell@user-ioc-keep"
zfs snapshot -r "$p/iocell@ioc-clone-keep"
zfs snapshot "$p/other@ioc-send-keep"
zfs snapshot -r "$p/iocell@ioc-send-old"
zfs snapshot "$root@ioc-send-blocked"
zfs clone "$root@ioc-send-blocked" "$p/outside"
guid=$(zfs get -H -o value guid "$p/outside")
user_guid=$(zfs get -H -o value guid "$root@user-ioc-keep")
run_cleanup () (
    . ./lib/ioc-common
    . ./lib/ioc-zfs
    pool="$p"
    if [ "$1" = query ]; then
        zfs () {
            if [ "$1" = list ]; then echo 'injected cleanup query failure' >&2; return 42; fi
            command zfs "$@"
        }
    fi
    __clean_snapshots
)
zfs list -Hrt all -o name "$p" > "$workdir/before"
status=0
run_cleanup query > "$workdir/query.log" 2>&1 || status=$?
[ "$status" = 42 ]
grep -q 'injected cleanup query failure' "$workdir/query.log"
zfs list -Hrt all -o name "$p" > "$workdir/after-query"
cmp "$workdir/before" "$workdir/after-query"
echo 'PASS: native cleanup query failure propagates without namespace changes'
status=0
run_cleanup normal > "$workdir/clone.log" 2>&1 || status=$?
[ "$status" = 1 ]
grep -q 'dependent clones' "$workdir/clone.log"
[ "$(zfs get -H -o value guid "$p/outside")" = "$guid" ]
zfs list "$root@ioc-send-blocked" >/dev/null
[ "$(cat "$mp/marker")" = preserved ]
echo 'PASS: native managed snapshot cleanup refuses dependent clones without destroying them'
# Explicitly remove only this test's blocker to exercise successful cleanup.
zfs destroy "$p/outside"
run_cleanup normal > "$workdir/success.log" 2>&1
if zfs list -Hrt snapshot -o name "$p/iocell" | grep '@ioc-send-' > "$workdir/leftovers"; then
    echo 'FAIL: managed snapshots remain after cleanup' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$root@user-ioc-keep")" = "$user_guid" ]
zfs list "$root@ioc-clone-keep" "$p/other@ioc-send-keep" >/dev/null
[ "$(cat "$mp/marker")" = preserved ]
echo 'PASS: native cleanup removes only owned send points and preserves user snapshots/data'
[ "$(uclcmd get -qf "$IOC_TEST_ROOT/.default" pool)" = "$IOC_TEST_POOL" ]
echo 'PASS: snapshot cleanup preserves original activation'
zpool status -x
