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
legacy_log=''
cleanup () {
    for uuid in "$first" "$second" "$foreign" "$disabled"; do
        if jls -j "ioc-$uuid" jid >/dev/null 2>&1; then
            jail -r "ioc-$uuid" || return 1
        fi
    done
    if [ -n "$legacy_log" ] && [ -L "$legacy_log" ] &&
        [ "$(readlink "$legacy_log")" = "$workdir/background-canary" ]; then
        rm -f -- "$legacy_log"
    fi
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
    if [ "$1" = "$IOC_RC_FIRST" ]; then
        case "$IOC_RC_FAULT" in
            return) return 42 ;; exit) exit 43 ;;
            background-*)
                echo 'injected native background failure' >&2
                [ "$IOC_RC_FAULT" != background-exit ] || exit 43
                return 42 ;;
        esac
    fi
    jail -c "name=ioc-$1" "path=$iocroot/jails/$1/root" persist \
        ip4=disable ip6=disable || return $?
    printf '%s\n' "$1" >> "$IOC_RC_EVENTS"
}
__stop_jail () {
    if [ "$1" = "$IOC_RC_SECOND" ]; then
        case "$IOC_RC_FAULT" in return) return 42 ;; exit) exit 43 ;; esac
    fi
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
        IOC_RC_FIRST="$first" IOC_RC_SECOND="$second" \
        IOC_RC_FAULT="${IOC_RC_FAULT:-none}" \
        IOC_RC_ENUM_FAULT="${IOC_RC_ENUM_FAULT:-no}" sh "$workdir/rc.sh" "$1"
}
echo 'log path canary' > "$root/log"
: > "$workdir/events"; status=0
backend_rc boot > "$workdir/log-setup.log" 2>&1 || status=$?
if [ "$status" != 1 ] || [ -s "$workdir/events" ] ||
    [ "$(cat "$root/log")" != 'log path canary' ] ||
    ! grep -F "cannot create log directory: $root/log" "$workdir/log-setup.log" >/dev/null ||
    grep -E -q 'background start failed|; see ' "$workdir/log-setup.log"; then
    echo 'FAIL: native rc boot lost log setup failure or attempted a jail' >&2
    exit 1
fi
for uuid in "$first" "$second"; do
    if jls -j "ioc-$uuid" jid >/dev/null 2>&1; then exit 1; fi
done
rm "$root/log"
echo 'PASS: native rc boot preserves a blocked log path and stops before jail creation'
: > "$workdir/events"
( umask 000; backend_rc boot ) > "$workdir/boot.log" 2>&1
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
for action in boot shutdown; do
    for fault in return exit; do
        cleanup
        if [ "$action" = shutdown ]; then backend_rc boot > "$workdir/setup.log" 2>&1; fi
        : > "$workdir/events"; status=0; want=42
        [ "$fault" != exit ] || want=43
        IOC_RC_FAULT="$fault" backend_rc "$action" > "$workdir/$action-$fault.log" 2>&1 || status=$?
        [ "$status" = "$want" ]
        if [ "$action" = boot ]; then
            echo "$second" > "$workdir/expected"
            jls -j "ioc-$second" jid > "$workdir/later-jid"
            if jls -j "ioc-$first" jid >/dev/null 2>&1; then exit 1; fi
        else
            echo "$first" > "$workdir/expected"
            jls -j "ioc-$second" jid > "$workdir/failed-stop-jid"
            if jls -j "ioc-$first" jid >/dev/null 2>&1; then exit 1; fi
        fi
        cmp "$workdir/events" "$workdir/expected"
        echo "PASS: native rc $action $fault preserves failure and performs the later kernel action"
    done
done
cleanup
# Priority changes are confined to these owned fixtures and restored bytewise.
printf 'host_hostuuid="%s"; boot="on"; hostid="%s"; priority=99;\n' \
    "$first" "$(cat /etc/hostid)" > "$root/jails/$first/config"
printf 'host_hostuuid="%s"; boot="off"; hostid="%s"; priority=20;\n' \
    "$second" "$(cat /etc/hostid)" > "$root/jails/$second/config"
# A different UID can plant this old predictable path, but cannot write the
# root-only target. The rc logger must leave both link and canary untouched.
echo 'preserved root-only canary' > "$workdir/background-canary"
chmod 600 "$workdir/background-canary"
cp "$workdir/background-canary" "$workdir/background-canary.before"
[ ! -e "/var/tmp/$first" ] && [ ! -L "/var/tmp/$first" ]
env SHELL=/bin/sh su -m nobody -c \
    "ln -s '$workdir/background-canary' '/var/tmp/$first'" \
    > "$workdir/untrusted-link.log" 2>&1
[ "$(stat -f %u "/var/tmp/$first")" = "$(id -u nobody)" ]
legacy_log="/var/tmp/$first"
background_log="$root/log/$first-rcboot.log"
for fault in background-return background-exit; do
    output=$(
        umask 000
        status=0
        IOC_RC_FAULT="$fault" backend_rc boot 2>&1 || status=$?
        printf '\nrc-status=%s\n' "$status"
    )
    printf '%s\n' "$output" > "$workdir/$fault.log"
    grep -qx 'rc-status=0' "$workdir/$fault.log"
    if ! cmp -s "$workdir/background-canary" "$workdir/background-canary.before"; then
        echo 'FAIL: background start followed an untrusted legacy log symlink' >&2
        exit 1
    fi
    [ -L "$legacy_log" ]
    [ "$(stat -f %u "$root/log")" = 0 ]
    log_mode=$(stat -f %Lp "$root/log")
    if [ "$((0$log_mode & 0022))" != 0 ]; then
        echo 'FAIL: background log directory permits untrusted writes' >&2
        exit 1
    fi
    grep -q 'injected native background failure' "$background_log"
    grep -F "background start failed for $first; see $background_log" "$workdir/$fault.log"
    echo "PASS: native rc $fault preserves canary, retains protected log and reports failure with status 0"
done
cp "$workdir/$first.config" "$root/jails/$first/config"
cp "$workdir/$second.config" "$root/jails/$second/config"
for uuid in "$first" "$second" "$foreign" "$disabled"; do
    cmp "$root/jails/$uuid/config" "$workdir/$uuid.config"
    [ "$(cat "$root/jails/$uuid/root/canary")" = preserved ]
    [ "$(zfs get -H -o value guid "$p/iocell/jails/$uuid/root")" = \
        "$(cat "$workdir/$uuid.guid")" ]
done
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: native rc lifecycle preserves config, data, GUIDs and activation'
zpool status -x
