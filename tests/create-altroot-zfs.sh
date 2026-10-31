#!/bin/sh
# Real create/clone backends with an altroot, not a mock configuration writer.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
before=$(sha256 -q "$IOC_TEST_ROOT/.default")
workdir=$(mktemp -d /var/tmp/iocell-create-altroot.XXXXXX)
p=$(ioc_test_pool_name iocalt)
echo "Retained altroot creation logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -R "$workdir/altroot" -O mountpoint=none "$p" "$workdir/pool.vdev"
zfs create -o mountpoint=/iocell "$p/iocell"
zfs create "$p/iocell/jails"; zfs create "$p/iocell/templates"
zfs create "$p/iocell/releases"
root=$(zfs get -H -o value mountpoint "$p/iocell")
cat > "$workdir/backend.sh" <<'HELPER'
#!/bin/sh
set +u
. ./lib/ioc-globals
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-configure
. ./lib/ioc-zfs
. ./lib/ioc-hacks
pool="$ALT_POOL"; iocroot="$ALT_ROOT"; uuid="$ALT_ID"
host_hostuuid="$uuid"; host_hostname="$uuid"; tag="$ALT_TAG"
compression=lz4; pkglist=none; hack88=0; start=''
case "$1" in
    create) __create_jail create -e ;;
    clone) __clone_jail "$2" ;;
esac
HELPER
id=$(uuidgen)
env ALT_POOL="$p" ALT_ROOT="$root" ALT_ID="$id" ALT_TAG=altroot-source \
    sh "$workdir/backend.sh" create > "$workdir/create.out" 2> "$workdir/create.err"
[ "$(cat "$workdir/create.out")" = "$id" ]
ds="$p/iocell/jails/$id"; mp=$(zfs get -H -o value mountpoint "$ds")
[ "$(uclcmd get -qf "$mp/config" host_hostuuid)" = "$id" ]
[ "$(zfs get -H -o value compression "$ds")" = lz4 ]
echo 'PASS: native altroot create configures the dataset, not its filesystem path'
mkdir -p "$mp/root/etc"
echo 'hostname="source"' > "$mp/root/etc/rc.conf"
echo preserved > "$mp/root/canary"
cp "$mp/config" "$workdir/source-before"
guid=$(zfs get -H -o value guid "$ds/root")
zfs snapshot -r "$ds@saved"
copy=$(uuidgen)
env ALT_POOL="$p" ALT_ROOT="$root" ALT_ID="$copy" ALT_TAG=altroot-copy \
    sh "$workdir/backend.sh" clone "$id@saved" > "$workdir/clone.out" 2> "$workdir/clone.err"
copyds="$p/iocell/jails/$copy"; copymp=$(zfs get -H -o value mountpoint "$copyds")
[ "$(zfs get -H -o value compression "$copyds")" = lz4 ]
[ "$(uclcmd get -qf "$copymp/config" host_hostuuid)" = "$copy" ]
[ "$(readlink "$root/tags/altroot-copy")" = "../jails/$copy" ]
[ "$(cat "$copymp/root/canary")" = preserved ]
echo 'PASS: native altroot clone uses the canonical dataset and a relative alias'
cmp "$mp/config" "$workdir/source-before"
[ "$(zfs get -H -o value guid "$ds/root")" = "$guid" ]
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: altroot creation preserves source config, GUID and original activation'
zpool status -x
