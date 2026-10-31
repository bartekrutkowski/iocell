#!/bin/sh
# Real discovery/UCL/rc selection, with kernel jails in a private scratch pool.
# Minimal persist jails test selection, not the full userland startup backend.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
before=$(sha256 -q "$IOC_TEST_ROOT/.default")
workdir=$(mktemp -d /var/tmp/iocell-rc-zfs.XXXXXX)
p=$(ioc_test_pool_name iocrc)
echo "Retained rc logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
zfs create -o mountpoint="$workdir/tree" "$p/iocell"
zfs create "$p/iocell/jails"
zfs create "$p/iocell/templates"
root="$workdir/tree"
first=$(uuidgen); second=$(uuidgen); foreign=$(uuidgen); disabled=$(uuidgen)
cleanup () {
    for uuid in "$first" "$second" "$foreign" "$disabled"; do
        if jls -j "ioc-$uuid" jid >/dev/null 2>&1; then
            jail -r "ioc-$uuid" || return 1
        fi
    done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
for uuid in "$first" "$second" "$foreign" "$disabled"; do
    zfs create "$p/iocell/jails/$uuid"
    zfs create "$p/iocell/jails/$uuid/root"
    boot=on; owner=$(cat /etc/hostid); priority=20
    case "$uuid" in
        "$first") priority=10 ;;
        "$foreign") owner=foreign-host ;;
        "$disabled") boot=off ;;
    esac
    printf 'host_hostuuid="%s"; tag="rc-%s"; boot="%s"; hostid="%s"; priority=%s;\n' \
        "$uuid" "$uuid" "$boot" "$owner" "$priority" > "$root/jails/$uuid/config"
    echo preserved > "$root/jails/$uuid/root/canary"
    zfs get -H -o value guid "$p/iocell/jails/$uuid/root" > "$workdir/$uuid.guid"
    cp "$root/jails/$uuid/config" "$workdir/$uuid.config"
done
cat > "$workdir/rc.sh" <<'HELPER'
#!/bin/sh
set +u
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-rc
pool="$IOC_RC_POOL"; iocroot="$IOC_RC_ROOT"; hostid=$(cat /etc/hostid)
__start_jail () {
    jail -c "name=ioc-$1" "path=$iocroot/jails/$1/root" persist \
        ip4=disable ip6=disable || return $?
    printf '%s\n' "$1" >> "$IOC_RC_EVENTS"
}
__stop_jail () {
    [ "$2" = "$pool/iocell/jails/$1" ] || return 99
    jail -r "ioc-$1" || return $?
    printf '%s\n' "$1" >> "$IOC_RC_EVENTS"
}
if [ "${IOC_RC_ENUM_FAULT:-no}" = yes ]; then
    zfs () {
        if [ "$1" = list ]; then
            echo 'injected rc discovery failure' >&2; return 42
        fi
        /sbin/zfs "$@"
    }
fi
__rc_jails "$1"
HELPER
backend_rc () {
    env IOC_RC_POOL="$p" IOC_RC_ROOT="$root" IOC_RC_EVENTS="$workdir/events" \
        IOC_RC_ENUM_FAULT="${IOC_RC_ENUM_FAULT:-no}" sh "$workdir/rc.sh" "$1"
}
: > "$workdir/events"
backend_rc boot > "$workdir/boot.log" 2>&1
printf '%s\n' "$first" "$second" > "$workdir/expected"
if ! cmp -s "$workdir/events" "$workdir/expected"; then
    echo 'FAIL: native rc boot did not select the eligible UUIDs in order' >&2
    exit 1
fi
jls -j "ioc-$first" jid > "$workdir/first-running"
jls -j "ioc-$second" jid > "$workdir/second-running"
for uuid in "$foreign" "$disabled"; do
    if jls -j "ioc-$uuid" jid > "$workdir/$uuid.running" 2>&1; then
        echo 'FAIL: native rc boot ignored boot/hostid selection' >&2; exit 1
    fi
done
echo 'PASS: native rc boot selects and starts only eligible kernel jails in order'
: > "$workdir/events"
backend_rc shutdown > "$workdir/shutdown.log" 2>&1
printf '%s\n' "$second" "$first" > "$workdir/expected"
cmp "$workdir/events" "$workdir/expected"
for uuid in "$first" "$second"; do
    if jls -j "ioc-$uuid" jid > "$workdir/$uuid.stopped" 2>&1; then
        echo 'FAIL: native rc shutdown left a selected jail running' >&2; exit 1
    fi
done
echo 'PASS: native rc shutdown stops selected kernel jails in reverse order'
: > "$workdir/events"; status=0
IOC_RC_ENUM_FAULT=yes backend_rc boot > "$workdir/enumeration.log" 2>&1 || status=$?
[ "$status" = 42 ] && [ ! -s "$workdir/events" ]
grep -q 'injected rc discovery failure' "$workdir/enumeration.log"
echo 'PASS: native rc discovery failure reaches the caller without jail creation'
for uuid in "$first" "$second" "$foreign" "$disabled"; do
    cmp "$root/jails/$uuid/config" "$workdir/$uuid.config"
    [ "$(cat "$root/jails/$uuid/root/canary")" = preserved ]
    [ "$(zfs get -H -o value guid "$p/iocell/jails/$uuid/root")" = \
        "$(cat "$workdir/$uuid.guid")" ]
done
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: native rc lifecycle preserves config, data, GUIDs and activation'
zpool status -x
