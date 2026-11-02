#!/bin/sh
# Upgrade failures must restore owned config/data and retain recovery points.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-upgrade
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-upgrade.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; id=11111111-1111-1111-1111-111111111111
ds="tank/iocell/jails/$id"; iocset_release=15.1-RELEASE
__find_jail () { echo "$ds"; }
__check_name () { echo "$id"; }
__get_jail_prop () {
    case "$1" in type) [ "$fault" != metadata ] || return 40; echo basejail ;;
        mountpoint) echo "$mp" ;;
        release) command awk -F= '$1=="release" {print $2}' "$mp/config" ;;
        template) [ "$fault" != template ] && echo none || echo saved-template ;;
    esac
}
__set_jail_prop () {
    cp -p "$mp/config" "$mp/config.old" || return $?
    printf '%s\n' "$1" > "$mp/config"
    [ "$fault" != setter ] || return 46
}
__check_basejail () {
    current=$(__get_jail_prop release x)
    if [ "$current" = 15.1-RELEASE ] && [ "$fault" = layout ]; then return 47; fi
    touch "$state/base-mounted"
}
__umount_basejail () { rm -f "$state/base-mounted"; }
__mount_basejail () {
    touch "$state/base-mounted"
    [ "$fault" != layout ] || return 47
}
jls () { [ "$fault" != running ] || echo 11; }
date () { echo 2026-01-01; }
mount () {
    if [ "$1" = -p ]; then
        [ ! -f "$state/base-mounted" ] || printf '/release %s/usr/bin nullfs ro 0 0\n' "$mp/root"
        [ ! -f "$state/dev-mounted" ] || printf 'devfs %s/dev devfs rw 0 0\n' "$mp/root"
        return 0
    fi
    [ "$fault" != mount ] || return 44
    touch "$state/dev-mounted"
}
umount () {
    case "$fault:$(cat "$mp/config")" in
        cleanup:release=15.1-RELEASE|old-cleanup:*) return 50 ;;
    esac
    case "$1" in */usr/bin) rm -f "$state/base-mounted" ;;
        *) rm -f "$state/dev-mounted" ;; esac
}
cp () {
    if [ "$fault" = backup ] && [ "$1" = -Rp ]; then return 48; fi
    command cp "$@"
}
zfs () {
    echo "$*" >> "$state/zfs.trace"
    case "$1" in
        list) [ "$fault" != enumerate ] || return 41 ;;
        snapshot)
            [ "$fault" != snapshot ] || return 45
            command cp -Rp "$mp/root" "$state/snapshot"
            ;;
        rollback)
            [ "$fault" != backout ] || return 49
            case "$2" in *R*|*f*) echo 'unsafe rollback flags' >&2; return 99 ;; esac
            rm -rf "$mp/root"
            command cp -Rp "$state/snapshot" "$mp/root" ;;
        destroy) echo 'recovery snapshot must be retained' >&2; return 99 ;;
        *) return 99 ;;
    esac
}
chroot () {
    echo "$*" >> "$state/chroot.trace"
    case "$*" in
        *'etcupdate -F')
            [ -f "$state/dev-mounted" ] || return 97
            echo merged > "$mp/root/etc/canary"
            case "$fault" in build|backout) return 42 ;; esac ;;
        *'etcupdate resolve') [ "$fault" != resolve ] || return 43 ;;
        *'etcupdate status')
            case "$fault" in unresolved) echo '  C /etc/example' ;;
                warnings) printf 'Warnings:\nRemoved file changed: /COPYRIGHT\n' ;; esac ;;
    esac
    return 0
}
failed=0
for fault in build resolve mount snapshot setter layout backup backout cleanup old-cleanup running existing template enumerate unresolved metadata warnings success; do
    state="$workdir/$fault"; iocroot="$state/iocell"; mp="$iocroot/jails/$id"
    mkdir -p "$mp/root/etc" "$mp/root/dev" "$iocroot/releases/15.1-RELEASE"
    echo release=14.5-RELEASE > "$mp/config"
    echo original > "$mp/root/etc/canary"
    command cp "$mp/config" "$state/config.before"
    : > "$state/zfs.trace"; : > "$state/chroot.trace"
    want=0; case_failed=0
    case "$fault" in build|backout) want=42 ;; resolve) want=43 ;; mount) want=44 ;;
        snapshot) want=45 ;; setter) want=46 ;; layout) want=47 ;; backup) want=48 ;;
        cleanup|old-cleanup) want=50 ;; running|existing|template|unresolved) want=1 ;;
        enumerate) want=41 ;; metadata) want=40 ;;
    esac
    [ "$fault" != existing ] || { mkdir "$mp/etc.old"; echo saved > "$mp/etc.old/saved"; }
    status=0
    ( __upgrade "$id" ) > "$state/result.log" 2>&1 || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: upgrade $fault status=$status expected=$want"; failed=1; continue
    fi
    if [ "$want" = 0 ]; then
        [ "$(cat "$mp/root/etc/canary")" = merged ] &&
            [ "$(cat "$mp/config")" = release=15.1-RELEASE ] || case_failed=1
    else
        if grep -q 'upgraded successfully' "$state/result.log" ||
            ! cmp -s "$mp/config" "$state/config.before"; then
            echo "FAIL: upgrade $fault reported success or lost original config"; failed=1; continue
        fi
        case "$fault" in
            backout|cleanup)
                [ -d "$state/snapshot" ] && [ -d "$mp/etc.old" ] || case_failed=1
                grep -qi 'incomplete' "$state/result.log" || case_failed=1 ;;
            *) [ "$(cat "$mp/root/etc/canary")" = original ] || case_failed=1 ;;
        esac
        if [ "$fault" = build ] && grep -q 'etcupdate resolve' "$state/chroot.trace"; then
            echo 'FAIL: failed build continued to conflict resolution'; failed=1; continue
        fi
    fi
    if [ "$fault" = existing ] && [ "$(cat "$mp/etc.old/saved")" != saved ]; then case_failed=1; fi
    if [ "$case_failed" != 0 ]; then
        echo "FAIL: upgrade $fault lost data, recovery points or diagnostics"; failed=1
    else echo "PASS: upgrade $fault preserves status and recovery boundaries"; fi
done
exit "$failed"
