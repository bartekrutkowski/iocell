#!/bin/sh
# Actual nullfs errors are quiet in legacy mode and visible in strict mode.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-mount-diagnostics.XXXXXX)
echo "Retained mount diagnostic logs: $workdir"
root="$workdir/tree/jails/fixture/root"
mkdir -p "$root/var/ports/distfiles" "$root/var/ports/packages" \
    "$root/compat" "$root/usr/obj" "$root/bin" "$root/tmp"
cleanup () { umount "$root/tmp" >/dev/null 2>&1 || :; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
cat > "$workdir/mount.sh" <<'HELPER'
#!/bin/sh
. ./lib/ioc-common
. ./lib/ioc-zfs
iocroot="$MD_ROOT"; basedirs=bin
__mount_basejail fixture nonexistent "$1"
HELPER
env MD_ROOT="$workdir/tree" sh "$workdir/mount.sh" 0 \
    > "$workdir/legacy.out" 2> "$workdir/legacy.err"
if [ -s "$workdir/legacy.err" ]; then
    echo 'FAIL: native non-strict mount printed an error'; exit 1
fi
mount -p | awk -v target="$root/tmp" '$2==target && $3=="tmpfs" {found=1} END {exit !found}'
umount "$root/tmp"
echo 'PASS: native non-strict mount is quiet and continues after a failed layer'
status=0
env MD_ROOT="$workdir/tree" sh "$workdir/mount.sh" 1 \
    > "$workdir/strict.out" 2> "$workdir/strict.err" || status=$?
[ "$status" != 0 ] && [ -s "$workdir/strict.err" ]
grep -Fq "$workdir/tree/releases" "$workdir/strict.err"
if mount -p | awk -v target="$root/tmp" '$2==target {found=1} END {exit !found}'; then exit 1; fi
echo 'PASS: native strict mount reports the failed layer and stops before tmpfs'
