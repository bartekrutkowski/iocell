#!/bin/sh
# Actual mount records with literal spaces must preserve exact cleanup scope.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
. ./lib/ioc-common
workdir=$(mktemp -d /var/tmp/iocell-mount-path.XXXXXX)
echo "Retained literal mount-path logs: $workdir"
root="$workdir/root with 'quote[ab]"
mkdir -p "$root/first" "$root/second" "$root-neighbor"
cleanup () {
    umount "$root/second" >/dev/null 2>&1 || :
    umount "$root/first" >/dev/null 2>&1 || :
    umount "$root-neighbor" >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mount -t tmpfs tmpfs "$root/first"
mount -t tmpfs tmpfs "$root/second"
mount -t tmpfs tmpfs "$root-neighbor"
__mounts_below "$root" > "$workdir/actual"
printf '%s\n' "$root/second" "$root/first" > "$workdir/expected"
cmp "$workdir/actual" "$workdir/expected"
echo 'PASS: literal mount records are scoped and reversed without including neighbors'
