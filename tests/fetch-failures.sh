#!/bin/sh
# Failed fetch/setup must retain datasets, downloads and the original resolver.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-info
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-fetch.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; compression=lz4; ftpfiles=base.txz
uname () { echo 15.1-RELEASE-p6; }
sleep () { :; }
zfs () {
    echo "$*" >> "$state/zfs.trace"
    case "$1" in
        list)
            if [ "$2" = -H ] && [ "$3" = -o ]; then
                case "$*" in *download*) echo tank/iocell/download ;;
                    *) echo tank/iocell/releases
                        [ "$mode" != existing ] || echo tank/iocell/releases/15.1-RELEASE/root ;;
                esac
            elif [ "$mode" = existing ]; then echo tank/iocell/releases/15.1-RELEASE/root; fi ;;
        create)
            [ "$mode" != create ] || return 42
            mkdir -p "$root" "$download" ;;
        get)
            for last; do :; done
            case "$*" in *mountpoint*)
                case "$last" in *download*)
                        [ "$mode" != download-mount ] && echo "$download" || echo /unexpected ;;
                    */root) echo "$root" ;; *) echo "$iocroot/releases/15.1-RELEASE" ;; esac ;;
                *mounted*) [ "$mode" != unmounted ] && echo yes || echo no ;;
                *) echo tank/iocell/releases/15.1-RELEASE ;; esac ;;
        destroy) return 49 ;;
        *) return 99 ;;
    esac
}
fetch () {
    echo fetch >> "$state/actions"
    if [ "$1" = -o ]; then echo partial-download > "$2"
    else echo partial-download > base.txz; fi
    [ "$mode" != download ] || return 43
}
tar () {
    echo tar >> "$state/actions"
    mkdir -p "$root/etc" "$root/dev" "$root/usr/src"
    echo source > "$root/usr/src/Makefile"
    : > "$root/etc/freebsd-update.conf"
    ln -s "$state/host-canary" "$root/etc/resolv.conf"
    echo retained > "$root/data"
    [ "$mode" != extract ] || return 44
}
chflags () { :; }
jls () { :; }
mount () {
    if [ "${1:-}" = -p ]; then
        [ ! -f "$state/mounted" ] || printf 'devfs %s/dev devfs rw 0 0\n' "$root"
        return 0
    fi
    touch "$state/mounted"
}
umount () { [ "$mode" != cleanup ] || return 47; rm -f "$state/mounted"; }
chroot () {
    echo "$*" >> "$state/actions"
    case "$*" in
        *freebsd-update*) case "$mode" in patch|existing) return 45 ;; esac ;;
        *'etcupdate build'*)
            [ "$mode" != baseline ] || return 46
            [ "$mode" != interrupted ] || sh -c 'kill -TERM "$PPID"' ;;
    esac
}
failed=0
for mode in create download extract patch baseline cleanup existing interactive download-mount unmounted interrupted files-glob success; do
    state="$workdir/$mode"; iocroot="$state/iocell"
    root="$iocroot/releases/15.1-RELEASE/root"
    download="$iocroot/download/15.1-RELEASE"
    mkdir -p "$state" "$iocroot/releases" "$iocroot/download"
    echo unchanged > "$state/host-canary"
    : > "$state/zfs.trace"; : > "$state/actions"
    if [ "$mode" = existing ]; then
        mkdir -p "$download"; tar
        : > "$state/actions"
    fi
    iocset_release=15.1-RELEASE; ftplocaldir="$state"; ftpfiles=base.txz
    if [ "$mode" = files-glob ]; then
        ftpfiles='*.txz'; echo unrelated > "$state/unrelated.txz"
    fi
    case "$mode" in patch|existing) ftplocaldir= ;; interactive) iocset_release= ;; esac
    status=0; want=0
    case "$mode" in create) want=42 ;; download) want=43 ;; extract) want=44 ;;
        patch|existing) want=45 ;; baseline) want=46 ;; cleanup) want=47 ;;
        download-mount|unmounted|files-glob) want=1 ;; interrupted) want=143 ;; esac
    ( cd "$state"; printf '15.1-RELEASE\n' | __fetch_release ) \
        > "$state/result.log" 2>&1 || status=$?
    if [ "$status" != "$want" ] || [ "$(cat "$state/host-canary")" != unchanged ]; then
        echo "FAIL: fetch $mode status=$status expected=$want or changed resolver target"; failed=1
    elif grep -q '^destroy ' "$state/zfs.trace"; then
        echo "FAIL: fetch $mode attempted destructive cleanup"; failed=1
    elif [ "$mode" = existing ] && grep -Eq '^fetch$|^tar$' "$state/actions"; then
        echo 'FAIL: existing release was downloaded/re-extracted instead of patched'; failed=1
    elif [ "$mode" != create ] && [ "$mode" != download-mount ] &&
        [ "$mode" != unmounted ] && [ "$mode" != files-glob ] &&
        [ ! -f "$root/data" ] && [ "$mode" != download ]; then
        echo "FAIL: fetch $mode lost partially prepared release data"; failed=1
    elif [ -f "$root/data" ] && [ ! -L "$root/etc/resolv.conf" ]; then
        echo "FAIL: fetch $mode removed the original resolver link"; failed=1
    elif [ -L "$root/etc/resolv.conf" ] &&
        [ "$(readlink "$root/etc/resolv.conf")" != "$state/host-canary" ]; then
        echo "FAIL: fetch $mode lost original resolver link"; failed=1
    elif [ "$mode" != cleanup ] && [ -f "$state/mounted" ]; then
        echo "FAIL: fetch $mode leaked its devfs mount"; failed=1
    else echo "PASS: fetch $mode preserves failure status, data and resolver"; fi
done
exit "$failed"
