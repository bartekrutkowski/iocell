#!/bin/sh
# Opt-in native import checks. Only this run's image and jail fixture are reset.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname -s)" = FreeBSD ] && [ "$(id -u)" = 0 ] || exit 1
: "${IOC_TEST_POOL:?Set the activated disposable test pool}"
: "${IOC_TEST_RELEASE:?Set a fetched release}"
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
[ "$(iocell get pool default)" = "$IOC_TEST_POOL" ]
[ -d "/iocell/releases/$IOC_TEST_RELEASE/root" ]
workdir=$(mktemp -d /var/tmp/iocell-import-zfs.XXXXXX)
printf 'Retained import logs: %s\n' "$workdir"
uuid=$(iocell create -e "release=$IOC_TEST_RELEASE" "tag=import-test-$$")
printf '%s\n' "$uuid" | grep -Eq \
    '^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$'
iocell set type=basejail "$uuid"
ds="$IOC_TEST_POOL/iocell/jails/$uuid"
mp=$(zfs get -H -o value mountpoint "$ds")
printf 'Retained import fixture: %s\n' "$ds"
dd if=/dev/urandom of="$mp/root/import-marker" bs=1024 count=512 2>/dev/null
marker_hash=$(sha256 -q "$mp/root/import-marker")
cp "$mp/config" "$workdir/config-before"
zfs snapshot -r "$ds@import-fixture"
snapshot_guid=$(zfs get -H -o value guid "$ds/root@import-fixture")
root_guid=$(zfs get -H -o value guid "$ds/root")
zfs send -R "$ds@import-fixture" > "$workdir/good.stream"
mkdir -p /iocell/images
image="/iocell/images/$uuid-basejail-$(date +%F)_$IOC_TEST_RELEASE"
cp "$workdir/good.stream" "$image"
image_hash=$(sha256 -q "$image")

if iocell import "$uuid" > "$workdir/existing.log" 2>&1; then
    echo 'FAIL: existing jail was accepted' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$ds/root")" = "$root_guid" ]
[ "$(sha256 -q "$mp/root/import-marker")" = "$marker_hash" ]
cmp "$mp/config" "$workdir/config-before"
echo 'PASS: existing full-UUID jail is refused without changing data/config'

# Remove only our newly created fixture so each stream has a clean receiver.
zfs destroy -r "$ds"
printf 'not a ZFS stream\n' > "$image"
corrupt_hash=$(sha256 -q "$image")
if iocell import "$uuid" > "$workdir/corrupt.log" 2>&1; then
    echo 'FAIL: corrupt stream reported success' >&2; exit 1
fi
! grep -q 'done!' "$workdir/corrupt.log"
grep -q 'cannot receive' "$workdir/corrupt.log"
[ "$(sha256 -q "$image")" = "$corrupt_hash" ]
if zfs list "$ds" >/dev/null 2>&1; then
    echo 'FAIL: invalid header unexpectedly created a jail' >&2; exit 1
fi
echo 'PASS: corrupt stream returns failure, retains diagnostics/image, prints no success'

blocks=$(($(stat -f %z "$workdir/good.stream") / 2048))
[ "$blocks" -gt 0 ]
dd if="$workdir/good.stream" of="$image" bs=1024 count="$blocks" 2>/dev/null
truncated_hash=$(sha256 -q "$image")
if iocell import "$uuid" > "$workdir/truncated.log" 2>&1; then
    echo 'FAIL: truncated stream reported success' >&2; exit 1
fi
! grep -q 'done!' "$workdir/truncated.log"
grep -q 'cannot receive' "$workdir/truncated.log"
[ "$(sha256 -q "$image")" = "$truncated_hash" ]
# ZFS itself may roll back incomplete receives. If it leaves a namespace,
# record it and explicitly reset only this test fixture before the next case.
if zfs list "$ds" >/dev/null 2>&1; then
    zfs list -r "$ds" > "$workdir/partial-datasets.log"
    zfs destroy -r "$ds"
fi
echo 'PASS: truncated real stream returns failure without success or image changes'

cp "$workdir/good.stream" "$image"
mkdir "$workdir/bin"
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
/sbin/zfs "$@"
status=$?
if [ "$1" = recv ] && [ "$status" = 0 ]; then
    echo 'fixture receive: forced failure after completed stream' >&2
    exit 42
fi
exit "$status"
WRAPPER
chmod +x "$workdir/bin/zfs"
status=0
PATH="$workdir/bin:$PATH" iocell import "$uuid" \
    > "$workdir/after-receive.log" 2>&1 || status=$?
[ "$status" = 42 ]
! grep -q 'done!' "$workdir/after-receive.log"
grep -q 'fixture receive:' "$workdir/after-receive.log"
mp=$(zfs get -H -o value mountpoint "$ds")
[ "$(sha256 -q "$mp/root/import-marker")" = "$marker_hash" ]
cmp "$mp/config" "$workdir/config-before"
[ "$(sha256 -q "$image")" = "$image_hash" ]
echo 'PASS: receive error after data creation propagates and leaves image/data intact'
zfs destroy -r "$ds"

verify_restored () {
    mp=$(zfs get -H -o value mountpoint "$ds")
    [ "$(sha256 -q "$mp/root/import-marker")" = "$marker_hash" ]
    [ "$(zfs get -H -o value guid "$ds/root@import-fixture")" = "$snapshot_guid" ]
    cmp "$mp/config" "$workdir/config-before"
    [ "$(sha256 -q "$image")" = "$image_hash" ]
}
iocell import "$uuid" > "$workdir/valid.log" 2>&1
verify_restored
grep -q 'done!' "$workdir/valid.log"
echo 'PASS: valid image restores content, config and original snapshot GUID'

# A short selector must not overwrite an existing target via zfs receive.
short=$(printf '%s' "$uuid" | cut -c1-8)
restored_guid=$(zfs get -H -o value guid "$ds/root")
if iocell import "$short" > "$workdir/existing-short.log" 2>&1; then
    echo 'FAIL: short image selector accepted an existing jail' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$ds/root")" = "$restored_guid" ]
verify_restored
echo 'PASS: short image selection also preserves an existing jail'
zfs destroy -r "$ds"
iocell import "$short" > "$workdir/short.log" 2>&1
verify_restored
echo 'PASS: unique short image prefix restores to the full UUID'
zpool status -x
