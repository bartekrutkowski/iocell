#!/bin/sh
# Actual dataset identity and post-rename failure boundaries.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
workdir=$(mktemp -d /var/tmp/iocell-template-safety.XXXXXX)
echo "Retained template safety logs: $workdir"
tag="template-safety-$(uuidgen)"
uuid=$(iocell create -e "tag=$tag")
ds="$IOC_TEST_POOL/iocell/jails/$uuid"
template="$IOC_TEST_POOL/iocell/templates/$tag"
iocell set type=basejail jail_zfs=on "$uuid"
root_guid=$(zfs get -H -o value guid "$ds/root")
data_guid=$(zfs get -H -o value guid "$ds/data")
iocell set istemplate=yes "$uuid"
base_tag="colliding-base-$(uuidgen)"
base=$(iocell create -e "tag=$base_tag")
base_ds="$IOC_TEST_POOL/iocell/jails/$base"
iocell set type=basejail "$base"
base_mp=$(zfs get -H -o value mountpoint "$base_ds")
uclcmd set -u -f "$base_mp/config" -t string -- tag "$tag"
if iocell set istemplate=no "$base" > "$workdir/collision.log" 2>&1; then
    echo 'FAIL: already-jail source accepted template reversion' >&2; exit 1
fi
grep -q 'already a jail' "$workdir/collision.log"
[ "$(zfs get -H -o value jailed "$template/data")" = on ]
[ "$(zfs get -H -o value guid "$template/data")" = "$data_guid" ]
zfs list "$base_ds" >/dev/null
iocell set "tag=$base_tag" "$base"
echo 'PASS: colliding basejail tag cannot redirect template data state'

mkdir "$workdir/type-bin" "$workdir/link-bin"
cat > "$workdir/type-bin/uclcmd" <<'WRAPPER'
#!/bin/sh
for last; do :; done
if [ "$1" = set ] && [ "$last" = basejail ]; then
    echo 'injected post-rename type failure' >&2
    exit 42
fi
exec /usr/local/bin/uclcmd "$@"
WRAPPER
cat > "$workdir/link-bin/ln" <<WRAPPER
#!/bin/sh
for last; do :; done
if [ "\$last" = "$IOC_TEST_ROOT/tags/$tag" ]; then
    echo 'injected post-rename link failure' >&2
    exit 42
fi
exec /bin/ln "\$@"
WRAPPER
chmod +x "$workdir/type-bin/uclcmd" "$workdir/link-bin/ln"
for fault in type link; do
    status=0
    PATH="$workdir/$fault-bin:$PATH" iocell set istemplate=no "$tag" \
        > "$workdir/$fault-failure.log" 2>&1 || status=$?
    [ "$status" = 42 ]
    grep -q "injected post-rename $fault failure" "$workdir/$fault-failure.log"
    mp=$(zfs get -H -o value mountpoint "$ds")
    [ "$(uclcmd get -qf "$mp/config" istemplate)" = yes ]
    expected_type=template; [ "$fault" != link ] || expected_type=basejail
    [ "$(uclcmd get -qf "$mp/config" type)" = "$expected_type" ]
    [ "$(zfs get -H -o value jailed "$ds/data")" = on ]
    [ "$(zfs get -H -o value guid "$ds/root")" = "$root_guid" ]
    [ "$(zfs get -H -o value guid "$ds/data")" = "$data_guid" ]
    echo "PASS: native post-rename $fault error propagates before final flag update"
    # Repair only this intentionally interrupted test fixture explicitly.
    uclcmd set -u -f "$mp/config" -t string -- type basejail
    uclcmd set -u -f "$mp/config" -t string -- istemplate no
    if [ "$fault" = type ]; then iocell set istemplate=yes "$uuid"; fi
done
iocell set "tag=$tag" "$uuid"

# A legacy template with an unsafe destination must fail before deleting bin.
legacy=$(iocell create -e "tag=migrate-safety-$(uuidgen)")
legacy_ds="$IOC_TEST_POOL/iocell/jails/$legacy"
legacy_mp=$(zfs get -H -o value mountpoint "$legacy_ds")
zfs create "$legacy_ds/root/bin"
echo preserved > "$legacy_mp/root/bin/migration-marker"
guid=$(zfs get -H -o value guid "$legacy_ds/root/bin")
uclcmd set -u -f "$legacy_mp/config" -t string -- template yes
uclcmd set -u -f "$legacy_mp/config" -t string -- tag 'unsafe@legacy'
status=0
(
    set +u
    . ./lib/ioc-globals
    . ./lib/ioc-common
    . ./lib/ioc-info
    . ./lib/ioc-configure
    . ./lib/ioc-zfs
    pool="$IOC_TEST_POOL"; iocroot="$IOC_TEST_ROOT"
    __migrate_basejail "$legacy" 15.1-RELEASE
) > "$workdir/migration-preflight.log" 2>&1 || status=$?
[ "$status" = 1 ]
grep -q 'retag before migration' "$workdir/migration-preflight.log"
[ "$(zfs get -H -o value guid "$legacy_ds/root/bin")" = "$guid" ]
[ "$(cat "$legacy_mp/root/bin/migration-marker")" = preserved ]
echo 'PASS: native migration refuses unsafe template tag before destroying old datasets'
zpool status -x
