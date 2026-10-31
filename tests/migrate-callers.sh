#!/bin/sh
# Returned migration failures must stop the real helper and lifecycle callers.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-zfs
. ./lib/ioc-rc
. ./lib/ioc-upgrade
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-migration-callers.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; hostid=fixture-host
uuid=11111111-1111-1111-1111-111111111111
ds="tank/iocell/jails/$uuid"
__find_jail () { echo "$ds"; }
__hack88_mount () { :; }
__get_jail_prop () {
    case "$1" in
        type) echo basejail ;; istemplate) echo no ;;
        template) [ "$mode" = helper-modern ] && echo fixture-template || echo yes ;;
        tag) echo 'invalid@template' ;; hostid) echo "$hostid" ;;
        host_hostuuid) echo "$uuid" ;; mountpoint) echo "$mp" ;;
        release) echo fixture-RELEASE ;; interfaces) echo vnet0:bridge0 ;;
        vnet) echo on ;; bpf|dhcp|jail_zfs) echo off ;; *) echo 0 ;;
    esac
}
forbidden () { echo "$*" >> "$state/forbidden"; exit 99; }
__vnet_start () { forbidden kernel-start; }
__umount_basejail () { forbidden unmount-after-failure; }
__mount_template () {
    if [ "$mode" = helper-modern ]; then
        printf '%s %s\n' "$1" "$2" >> "$state/mounted"
    else forbidden "template-mount $2"; fi
}
__set_jail_prop () { :; }
jls () { :; }; sysctl () { echo 1; }
mount () { :; }; umount () { :; }
chroot () {
    case "$*" in *'etcupdate resolve') return 1 ;; esac
    return 0
}
zfs () {
    case "$1" in
        list)
            case "$mode" in
                helper-invalid)
                    i=1; while [ "$i" -le 17 ]; do
                        echo "$ds/root/legacy-$i"; i=$((i+1))
                    done ;;
                helper-modern) printf '%s\n' "$ds" "$ds/root" ;;
            esac ;;
        get)
            case " $* " in
                *' creation '*) return 1 ;;
                *' origin '*) echo 'fixture origin - -' ;;
                *) return 99 ;;
            esac ;;
        snapshot|rollback|destroy)
            [ "$mode" = upgrade-backout ] || forbidden "zfs $*"
            ;;
        *) forbidden "zfs $*" ;;
    esac
}
failed=0
for mode in helper-invalid helper-modern start-return start-exit \
    update-return update-exit upgrade-return upgrade-exit upgrade-backout; do
    state="$workdir/$mode"; iocroot="$state/tree"; mp="$iocroot/jails/$uuid"
    mkdir -p "$mp/root/etc" "$mp/root/usr/home" "$mp/root/usr/local" \
        "$iocroot/log" "$iocroot/releases/fixture-RELEASE/root/etc"
    : > "$iocroot/releases/fixture-RELEASE/root/etc/resolv.conf"
    : > "$iocroot/releases/fixture-RELEASE/root/etc/freebsd-update.conf"
    echo preserved > "$mp/root/etc/canary"
    : > "$state/forbidden"; : > "$state/mounted"
    want=42
    case "$mode" in helper-invalid) want=1 ;; helper-modern) want=0 ;; esac
    status=0
    (
        if [ "$mode" != helper-invalid ] && [ "$mode" != helper-modern ]; then
            calls=0
            __check_basejail () {
                calls=$((calls + 1))
                if [ "$mode" = upgrade-backout ] && [ "$calls" = 1 ]; then return 0; fi
                echo 'injected migration failure' >&2
                case "$mode" in *-exit) exit 42 ;; *) return 42 ;; esac
            }
        fi
        case "$mode" in
            helper-*) __check_basejail "$uuid" "$ds" ;;
            start-*) __start_jail "$uuid" ;;
            update-*) __update x x x "$uuid" ;;
            upgrade-*) iocset_release=fixture-RELEASE; __upgrade "$uuid" ;;
        esac
    ) > "$state/log" 2>&1 || status=$?
    if [ "$status" != "$want" ] || [ -s "$state/forbidden" ]; then
        echo "FAIL: migration $mode status=$status expected=$want or continued after failure"
        failed=1; continue
    fi
    if [ "$want" = 42 ] && ! grep -q 'injected migration failure' "$state/log"; then
        echo "FAIL: migration $mode hid the failure diagnostic"; failed=1; continue
    fi
    if [ "$mode" = helper-modern ]; then
        printf '%s %s\n' "$uuid" fixture-template > "$state/expected"
        cmp "$state/mounted" "$state/expected" || exit 1
    fi
    [ "$(cat "$mp/root/etc/canary")" = preserved ] || exit 1
    echo "PASS: migration $mode preserves status and stops later phases"
done
exit "$failed"
