#!/bin/sh
# AUTOIP4 consumers must not write config or start a jail after discovery fails.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-network
. ./lib/ioc-rc
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-autoip.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; hostid=fixture-host; fixture_uuid=11111111-1111-1111-1111-111111111111
fixture_ds="tank/iocell/jails/$fixture_uuid"
occupied_uuid=22222222-2222-2222-2222-222222222222
__find_jail () {
    echo "$fixture_ds"
    [ "$1" != ALL ] || echo "tank/iocell/jails/$occupied_uuid"
    if [ "$1" = ALL ] && [ "$fault" = yes ]; then
        echo failed > "$state/failed"; return 42
    fi
}
__check_name () { echo "$fixture_uuid"; }
__get_jail_prop () {
    case "$1" in
        type) echo basejail ;; hostid) echo fixture-host ;; istemplate) echo no ;;
        mountpoint) echo "$state/tree/jails/$fixture_uuid" ;; tag) echo fixture ;;
        release) echo fixture-RELEASE ;;
        ip4_addr)
            case "${3:-tank/iocell/jails/$2}" in
                "tank/iocell/jails/$occupied_uuid") echo 'lo0|192.0.2.10/24' ;;
                *) echo 'DEFAULT|AUTOIP4' ;;
            esac ;;
        ip4_autostart) echo 10 ;; ip4_autoend) echo 20 ;; ip4_autosubnet) echo 24 ;;
        ip6_addr|defaultrouter|defaultrouter6) echo none ;; interfaces) : ;;
        vnet) echo "$vnet" ;; cpuset|bpf|dhcp|jail_zfs) echo off ;; *) echo 0 ;;
    esac
}
__get_default_iface () { echo lo0; }
__hack88_mount () { :; }; __check_basejail () { :; }; __is_running () { :; }
__umount_basejail () { :; }
__vnet_start () { :; }
record () { [ ! -f "$state/failed" ] || echo "$*" >> "$trace"; }
__set_jail_prop () { record config-write; }
__rctl_limits () { record limits; return 99; }
__resolv_conf () { record resolver; }
jail () { record kernel-start; }
jexec () { record jail-command; }
ifconfig () { record interface-change; }
mount () { record mount; }
zfs () { echo 'fixture origin - -'; }
jls () { :; }; fgrep () { return 1; }
sysctl () { echo 1; }; uname () { echo 1501000; }
netstat () {
    case "$*" in '-iWn') printf 'bridge0\nbridge1\n' ;; *) echo 'default 192.0.2.1' ;; esac
}
failed=0
for label in legacy vnet start-legacy start-vnet; do
    for fault in yes no; do
        case "$label-$fault" in start-*-no) continue ;; esac
        state="$workdir/$label-$fault"; iocroot="$state/tree"
        mkdir -p "$iocroot/log" "$iocroot/jails/$fixture_uuid/root/dev" \
            "$iocroot/jails/$fixture_uuid/root/etc"
        trace="$state/trace"; : > "$trace"; status=0; want=0
        [ "$fault" != yes ] || want=42
        vnet=off; case "$label" in *vnet) vnet=on ;; esac
        (
            set +e
            ip4_addr='DEFAULT|AUTOIP4'
            case "$label" in legacy) __legacy_start "$fixture_uuid" "$fixture_ds" ;;
                vnet) __networking start "$fixture_uuid" "$fixture_ds" ;;
                *) __start_jail "$fixture_uuid" ;;
            esac
            status=$?
            [ "$fault" != no ] || [ "$auto_ip4" = 192.0.2.11/24 ] || exit 78
            exit "$status"
        ) > "$state/log" 2>&1 || status=$?
        if [ "$status" != "$want" ] || [ -s "$trace" ]; then
            echo "FAIL: auto-IP $label/$fault lost status=$status or continued after discovery failure"
            failed=1
        else echo "PASS: auto-IP $label/$fault preserves enumeration outcome"; fi
    done
done
exit "$failed"
