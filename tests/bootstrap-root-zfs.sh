#!/bin/sh
# Real CLI altroot selection while an unrelated normal /iocell directory exists.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
[ "$IOC_TEST_ROOT" = /iocell ] || {
    ioc_test_error 'bootstrap coexistence control requires a normal /iocell root'; exit 1;
}
[ -z "$(jls -n | grep 'name=ioc-' || :)" ] || exit 1
workdir=$(mktemp -d /var/tmp/iocell-bootstrap-zfs.XXXXXX)
p=$(ioc_test_pool_name iocboot)
echo "Retained CLI bootstrap logs/vdev: $workdir; pool: $p"
parent="$IOC_TEST_POOL"; canary=0; relocated=0; overlay=0
cp -p /iocell/.default "$workdir/original.default"
zfs list -H -p -r -t all -o name,guid "$parent/iocell" > "$workdir/original.guids"
cp -Rp . "$workdir/src"
mkdir "$workdir/bin"
# Do not allow an old implementation to mount unrelated retained pools.
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
if [ "${IOC_BOOT_FAIL_QUERY:-no}" = yes ] && [ "$1" = list ]; then
    echo 'injected bootstrap enumeration error' >&2
    exit 42
fi
if [ "$1" = mount ] && [ "${2:-}" = -a ]; then
    echo global-mount-intercepted >> "$IOC_BOOT_TRACE"
    exit 0
fi
exec /sbin/zfs "$@"
WRAPPER
chmod +x "$workdir/bin/zfs"
export IOC_BOOT_TRACE="$workdir/global-mounts"
PATH="$workdir/bin:$PATH"; export PATH
restore () {
    if [ "$canary" = 1 ]; then
        [ ! -f /iocell/.default ] || mv /iocell/.default "$workdir/host-default.after"
        canary=0
    fi
    if [ "$overlay" = 1 ]; then
        /sbin/umount /iocell || return 1
        overlay=0
    fi
    if [ "$relocated" = 1 ]; then
        /sbin/zfs set mountpoint=/iocell "$parent/iocell" || return 1
        cp -p "$workdir/original.default" /iocell/.default || return 1
        relocated=0
    fi
}
trap 'result=$?; restore || exit 1; exit "$result"' EXIT
trap 'exit 1' HUP INT TERM
alt="$workdir/altroot"
[ "${IOC_BOOTSTRAP_SPECIAL:-no}" != yes ] || alt="$workdir/alt root'&[ab] \$(touch injected)"
truncate -s 128M "$workdir/pool.vdev"
zpool create -R "$alt" -O mountpoint=none "$p" "$workdir/pool.vdev"
# Protect any unknown host-underlay files with an owned nullfs control view.
/sbin/zfs set mountpoint="$workdir/parent-held" "$parent/iocell"
relocated=1
mkdir "$workdir/normal-underlay"
/sbin/mount -t nullfs "$workdir/normal-underlay" /iocell
overlay=1
printf 'pool="%s"; notes="owned-bootstrap-canary";\n' "$parent" > /iocell/.default
canary=1
cp -p /iocell/.default "$workdir/host-default.before"
cd "$workdir/src"
sh ./iocell activate "$p" > "$workdir/activate.log" 2>&1
root=$(/sbin/zfs get -H -o value mountpoint "$p/iocell")
[ "$(uclcmd get -qf "$root/.default" pool)" = "$p" ]
cmp /iocell/.default "$workdir/host-default.before"
id=$(sh ./iocell create -e "tag=bootstrap-$(uuidgen)")
mp=$(/sbin/zfs get -H -o value mountpoint "$p/iocell/jails/$id")
[ -f "$mp/config" ] && [ -f "$mp/fstab" ]
[ "$(sh ./iocell get host_hostuuid "$id")" = "$id" ]
[ ! -e "$workdir/src/injected" ]
[ ! -e "$IOC_BOOT_TRACE" ]
echo 'PASS: real CLI activation/create/get uses selected altroot and literal persisted path'
# Preserve the canary before normal activation covers its host directory again.
mv /iocell/.default "$workdir/host-default.after"; canary=0
/sbin/umount /iocell; overlay=0
sh ./iocell activate "$parent" > "$workdir/restore-activate.log" 2>&1
relocated=0
cmp /iocell/.default "$workdir/original.default"
zfs list -H -p -r -t all -o name,guid "$parent/iocell" > "$workdir/restored.guids"
cmp "$workdir/original.guids" "$workdir/restored.guids"
echo 'PASS: altroot CLI test preserves parent GUIDs, defaults and host canary'
status=0
env IOC_BOOT_FAIL_QUERY=yes sh ./iocell get pool default \
    > "$workdir/query-failure.log" 2>&1 || status=$?
[ "$status" = 42 ]
echo 'PASS: public entrypoint preserves initialization failure before dispatch'
