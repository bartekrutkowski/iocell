#!/bin/sh
# Opt-in native import checks. Only this run's image and jail fixture are reset.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set a fetched release}"
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
[ -d "$IOC_TEST_ROOT/releases/$IOC_TEST_RELEASE/root" ] || {
    ioc_test_error "release $IOC_TEST_RELEASE has not been fetched"; exit 1;
}
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
if iocell import "$uuid" notes=ignored > "$workdir/properties.log" 2>&1; then
    echo 'FAIL: ordinary import silently accepted property operands' >&2; exit 1
fi
if zfs list "$ds" >/dev/null 2>&1; then exit 1; fi
[ "$(sha256 -q "$image")" = "$image_hash" ]
mv "$image" "$image.partial"
if iocell import "$uuid" > "$workdir/partial-selection.log" 2>&1; then exit 1; fi
if zfs list "$ds" >/dev/null 2>&1; then exit 1; fi
mv "$image.partial" "$image"
echo 'PASS: ordinary import rejects ignored properties and incomplete images before receive'
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

# Ordinary exports of empty jails remain raw streams, not renamed tar archives.
empty=$(iocell create -e "release=$IOC_TEST_RELEASE" "tag=empty-image-$(uuidgen)")
emptyds="$IOC_TEST_POOL/iocell/jails/$empty"
emptymp=$(zfs get -H -o value mountpoint "$emptyds")
echo empty-image > "$emptymp/root/marker"
cp "$emptymp/config" "$workdir/empty.config"
iocell export "$empty" > "$workdir/empty.export" 2>&1
zfs rename "$emptyds" "$IOC_TEST_POOL/import-retained-$empty"
iocell import "$empty" > "$workdir/empty.import" 2>&1
emptymp=$(zfs get -H -o value mountpoint "$emptyds")
[ "$(cat "$emptymp/root/marker")" = empty-image ]
cmp "$emptymp/config" "$workdir/empty.config"
echo 'PASS: actual empty-jail export/import restores raw stream data and config'

# Legacy tar archives retain their distinct property-aware creation interface.
legacy=$(uuidgen); tag="legacy-image-$legacy"
mkdir -p "$workdir/legacy/etc"
printf 'hostname="old"\n' > "$workdir/legacy/etc/rc.conf"
legacy_image="$IOC_TEST_ROOT/images/${legacy}_$IOC_TEST_RELEASE.tar.xz"
tar -cJf "$legacy_image" -C "$workdir/legacy" .
sha256 -q "$legacy_image" > "${legacy_image%.tar.xz}.sha256"
iocell import "$legacy" "tag=$tag" 'notes=legacy preserved' \
    > "$workdir/legacy.import" 2>&1
[ "$(iocell get type "$tag")" = thickjail ]
[ "$(iocell get notes "$tag")" = 'legacy preserved' ]
[ -f "$legacy_image" ]
echo 'PASS: legacy archive properties remain supported without renaming the image'

bad=$(uuidgen)
bad_image="$IOC_TEST_ROOT/images/${bad}_$IOC_TEST_RELEASE.tar.xz"
# Leave enough compressed data to extract /etc before a late stream error.
dd if=/dev/urandom of="$workdir/legacy/zz-data" bs=1024 count=1024 2>/dev/null
tar -cJf "$workdir/legacy-full.tar.xz" -C "$workdir/legacy" etc zz-data
bytes=$(stat -f %z "$workdir/legacy-full.tar.xz")
dd if="$workdir/legacy-full.tar.xz" of="$bad_image" bs=1 \
    count=$((bytes - 8)) 2>/dev/null
sha256 -q "$bad_image" > "${bad_image%.tar.xz}.sha256"
if iocell import "$bad" "tag=bad-legacy-$bad" \
    > "$workdir/legacy.bad" 2>&1; then
    echo 'FAIL: legacy archive extraction failure reported success' >&2; exit 1
fi
[ -f "$bad_image" ]
echo 'PASS: legacy extraction failure is nonzero and preserves its archive'
zpool status -x
