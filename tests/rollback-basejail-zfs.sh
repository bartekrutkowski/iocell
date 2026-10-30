#!/bin/sh
# Real runnable basejail boundary: files/config, not properties/aliases/release.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set IOC_TEST_RELEASE to a fetched FreeBSD release}"
release="$IOC_TEST_ROOT/releases/$IOC_TEST_RELEASE/root"
[ -x "$release/bin/sh" ] || { echo 'FAIL: fetched release is unavailable' >&2; exit 1; }
workdir=$(mktemp -d /var/tmp/iocell-rollback-base.XXXXXX)
echo "Retained real-basejail rollback logs: $workdir"
iocell () { sh ./iocell "$@"; }
uuid=''; shared=''
cleanup () {
    status=$?
    trap - EXIT
    if [ -n "$uuid" ] && jls -j "ioc-$uuid" jid >/dev/null 2>&1; then
        iocell stop "$uuid" > "$workdir/stop.log" 2>&1 || status=1
    fi
    [ -z "$shared" ] || rm -f "$shared"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
original_tag="rollback-boundary-$(uuidgen)"
iocell create "release=$IOC_TEST_RELEASE" "tag=$original_tag" \
    type=basejail vnet=off count=1 > "$workdir/create.log"
uuid=$(awk '/Successfully created:/ {print $3}' "$workdir/create.log")
[ -n "$uuid" ]
ds="$IOC_TEST_POOL/iocell/jails/$uuid"
mp=$(zfs get -H -o value mountpoint "$ds")
inside="/usr/bin/.iocell-rollback-$uuid"
shared="$release$inside"
[ ! -e "$shared" ]
echo shared-before > "$shared"
echo root-before > "$mp/root/boundary-marker"
iocell set compression=off "$uuid"
iocell start "$uuid" > "$workdir/start-before.log" 2>&1
[ "$(iocell exec "$uuid" /bin/cat "$inside")" = shared-before ]
iocell stop "$uuid" > "$workdir/stop-before.log" 2>&1
echo 'PASS: real basejail starts and reads the shared release file'
cp "$mp/config" "$workdir/config-before"
iocell snapshot -f -r "$uuid@boundary"
renamed="renamed-$(uuidgen)"
iocell set "tag=$renamed" compression=gzip "$uuid"
echo root-after > "$mp/root/boundary-marker"
echo shared-after > "$shared"
[ -L "$IOC_TEST_ROOT/tags/$renamed" ]
[ ! -L "$IOC_TEST_ROOT/tags/$original_tag" ]
iocell rollback "$uuid@boundary" > "$workdir/rollback.log" 2>&1
cmp "$workdir/config-before" "$mp/config"
[ "$(cat "$mp/root/boundary-marker")" = root-before ]
[ "$(iocell get tag "$uuid")" = "$original_tag" ]
echo 'PASS: recursive basejail rollback restores root bytes and saved configuration'
[ "$(zfs get -H -o value compression "$ds")" = gzip ]
[ -L "$IOC_TEST_ROOT/tags/$renamed" ]
[ ! -L "$IOC_TEST_ROOT/tags/$original_tag" ]
echo 'PASS: rollback leaves native properties and tag symlink namespace unchanged'
iocell start "$uuid" > "$workdir/start-after.log" 2>&1
[ "$(iocell exec "$uuid" /bin/cat "$inside")" = shared-after ]
iocell stop "$uuid" > "$workdir/stop-after.log" 2>&1
echo 'PASS: basejail still reads newer shared-release content after jail rollback'
# Explicitly reconcile this fixture's alias; rollback itself must not silently
# steal a tag name that might now belong to a different jail.
iocell set "tag=$original_tag" "$uuid"
echo "Retained runnable basejail and snapshot: $ds@boundary"
zpool status -x
