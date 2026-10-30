#!/bin/sh
# Dependency protection uses isolated UUID pools, without changing activation.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-dependents-zfs.XXXXXX)
p=$(ioc_test_pool_name iocdeps)
echo "Retained dependency logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
clean_templates () (
    . ./lib/ioc-common
    . ./lib/ioc-zfs
    pool="$p"; _force="$1"
    __clean_templates
)
zfs create -p "$p/iocell/templates/first/root"
zfs snapshot "$p/iocell/templates/first/root@base"
zfs clone -p "$p/iocell/templates/first/root@base" "$p/iocell/templates/second/root"
printf 'y\n' | clean_templates 0 > "$workdir/internal.log" 2>&1
if zfs list "$p/iocell/templates" >/dev/null 2>&1; then
    echo 'FAIL: recursive cleanup retained its internal clone tree' >&2; exit 1
fi
echo 'PASS: native non-force cleanup removes internal template clones without -R'

zfs create -p "$p/iocell/templates/first/root"
zfs snapshot "$p/iocell/templates/first/root@base"
zfs clone "$p/iocell/templates/first/root@base" "$p/outside-root"
first_guid=$(zfs get -H -o value guid "$p/iocell/templates/first/root")
clone_guid=$(zfs get -H -o value guid "$p/outside-root")
if printf 'y\n' | clean_templates 0 > "$workdir/external.log" 2>&1; then
    echo 'FAIL: external root clone was ignored' >&2; exit 1
fi
grep -F "$p/outside-root" "$workdir/external.log"
[ "$(zfs get -H -o value guid "$p/iocell/templates/first/root")" = "$first_guid" ]
[ "$(zfs get -H -o value guid "$p/outside-root")" = "$clone_guid" ]
echo 'PASS: native non-force cleanup reports and preserves external clone GUIDs'

zfs create -p "$p/iocell/templates/data-only/data"
zfs snapshot "$p/iocell/templates/data-only/data@base"
zfs clone "$p/iocell/templates/data-only/data@base" "$p/outside-data"
status=0
(
    . ./lib/ioc-common
    . ./lib/ioc-zfs
    pool="$p"
    __check_children data-only "$p/iocell/templates/data-only"
) > "$workdir/data-guard.log" 2>&1 || status=$?
[ "$status" = 1 ]
grep -F "$p/outside-data" "$workdir/data-guard.log"
echo 'PASS: native shared guard protects an external data-only clone'

clean_templates 1 > "$workdir/forced.log" 2>&1
grep -F "$p/outside-root" "$workdir/forced.log"
grep -F "$p/outside-data" "$workdir/forced.log"
for ds in "$p/outside-root" "$p/outside-data" "$p/iocell/templates"; do
    if zfs list "$ds" >/dev/null 2>&1; then
        echo "FAIL: explicit force did not remove $ds" >&2; exit 1
    fi
done
echo 'PASS: native force lists the external clones it explicitly destroys'
[ "$(uclcmd get -qf "$IOC_TEST_ROOT/.default" pool)" = "$IOC_TEST_POOL" ]
echo 'PASS: dependency tests preserve the original pool activation'
zpool status -x
