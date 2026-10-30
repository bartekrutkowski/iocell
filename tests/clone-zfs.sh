#!/bin/sh
# Actual root/delegated-data snapshots and failures, on an opted-in test pool.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
iocell () {
    env PATH="$PATH" IOC_CLONE_FAULT="${IOC_CLONE_FAULT:-}" \
        IOC_CLONE_TRACE="${IOC_CLONE_TRACE:-}" sh ./iocell "$@"
}
workdir=$(mktemp -d /var/tmp/iocell-clone-zfs.XXXXXX)
printf 'Retained clone logs: %s\n' "$workdir"
testid=$(uuidgen | tr -d '-')
source_uuid=$(iocell create -e "tag=clone-source-$testid")
source="$IOC_TEST_POOL/iocell/jails/$source_uuid"
printf 'Retained source: %s\n' "$source"
root=$(zfs get -H -o value mountpoint "$source/root")
mkdir -p "$root/etc"
echo 'hostname="source"' > "$root/etc/rc.conf"
iocell set type=basejail jail_zfs=on "$source_uuid"
echo saved-root > "$root/clone-marker"
write_data () {
    zfs set jailed=off "$source/data"
    zfs set "mountpoint=$workdir/source-data" "$source/data"
    [ "$(zfs get -H -o value mounted "$source/data")" = yes ] || zfs mount "$source/data"
    echo "$1" > "$workdir/source-data/clone-marker"
    zfs unmount "$source/data"
    zfs set jailed=on "$source/data"
}
write_data saved-data
zfs snapshot "$source/root@root-only"
zfs snapshot -r "$source@pair"
root_snapshot_guid=$(zfs get -H -o value guid "$source/root@pair")
data_snapshot_guid=$(zfs get -H -o value guid "$source/data@pair")
echo live-root > "$root/clone-marker"
write_data live-data
for snap in typo root-only; do
    zfs list -d1 -rH -o name "$IOC_TEST_POOL/iocell/jails" > "$workdir/before"
    if iocell clone "$source_uuid@$snap" "tag=clone-missing-$testid" \
        > "$workdir/missing-$snap.log" 2>&1; then
        echo "FAIL: missing snapshot accepted: $snap" >&2; exit 1
    fi
    grep -q 'clone snapshot not found:' "$workdir/missing-$snap.log"
    zfs list -d1 -rH -o name "$IOC_TEST_POOL/iocell/jails" > "$workdir/after"
    cmp "$workdir/before" "$workdir/after"
    echo "PASS: native clone $snap fails before destination creation"
done
for mode in explicit automatic; do
    argument="$source_uuid@pair"; expected_root=saved-root; expected_data=saved-data
    if [ "$mode" = automatic ]; then
        argument="$source_uuid"; expected_root=live-root; expected_data=live-data
    fi
    tag="clone-$mode-$testid"
    iocell clone "$argument" "tag=$tag" jail_zfs=on > "$workdir/$mode.log" 2>&1
    target_uuid=$(iocell get host_hostuuid "$tag")
    target="$IOC_TEST_POOL/iocell/jails/$target_uuid"
    target_root=$(zfs get -H -o value mountpoint "$target/root")
    [ "$(cat "$target_root/clone-marker")" = "$expected_root" ]
    [ "$(zfs get -H -o value jailed "$target/data")" = on ]
    zfs set jailed=off "$target/data"
    zfs set "mountpoint=$workdir/$mode-data" "$target/data"
    [ "$(zfs get -H -o value mounted "$target/data")" = yes ] || zfs mount "$target/data"
    [ "$(cat "$workdir/$mode-data/clone-marker")" = "$expected_data" ]
    zfs unmount "$target/data"
    zfs set mountpoint=none jailed=on "$target/data"
    [ "$(iocell get type "$target_uuid")" = clonejail ]
    echo "PASS: native $mode clone preserves root and delegated data bytes"
done
mkdir "$workdir/bin"
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
set -eu
for last; do :; done
if [ "$1" = create ]; then echo "$last" > "$IOC_CLONE_TRACE"; fi
if [ "$1" = clone ] && [ "${last##*/}" = "$IOC_CLONE_FAULT" ]; then
    echo "injected $IOC_CLONE_FAULT clone failure" >&2
    exit 42
fi
exec /sbin/zfs "$@"
WRAPPER
chmod +x "$workdir/bin/zfs"
for fault in root data; do
    status=0
    PATH="$workdir/bin:$PATH" IOC_CLONE_FAULT="$fault" \
        IOC_CLONE_TRACE="$workdir/$fault.target" \
        iocell clone "$source_uuid@pair" "tag=clone-fail-$fault-$testid" \
        > "$workdir/failure-$fault.log" 2>&1 || status=$?
    [ "$status" = 42 ]
    grep -q "injected $fault clone failure" "$workdir/failure-$fault.log"
    ! grep -q 'Successfully created' "$workdir/failure-$fault.log"
    partial=$(cat "$workdir/$fault.target")
    partial_root=$(zfs get -H -o value mountpoint "$partial")
    [ ! -e "$partial_root/config" ]
    [ ! -L "$IOC_TEST_ROOT/tags/clone-fail-$fault-$testid" ]
    echo "PASS: native $fault clone error propagates without config or alias publication"
done
[ "$(zfs get -H -o value guid "$source/root@pair")" = "$root_snapshot_guid" ]
[ "$(zfs get -H -o value guid "$source/data@pair")" = "$data_snapshot_guid" ]
[ "$(cat "$root/clone-marker")" = live-root ]
echo 'PASS: source content and explicit root/data snapshot GUIDs remain unchanged'
zpool status -x
