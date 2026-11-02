#!/bin/sh
# Live jails/collisions refuse; failed image stages preserve recovery data.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-image
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-export.XXXXXX")
trap 'command rm -rf "$workdir"' EXIT
pool=tank; id=11111111-1111-1111-1111-111111111111
ds="tank/iocell/jails/$id"
__find_jail () { echo "$ds"; }
__check_name () { echo "$id"; }
__get_jail_prop () {
    case "$1" in type) [ "$mode" != legacy ] && echo emptyjail || echo jail ;;
        release) echo 15.1-RELEASE ;; tag) echo fixture ;; mountpoint) echo "$mp" ;; esac
}
__set_jail_prop () { return 48; }
date () { echo 2026-01-01; }
jls () {
    [ "$mode" != query ] || return 47
    if [ "$mode" = running ]; then
        if [ "$#" = 0 ]; then echo '11 192.0.2.1 fixture /truncated/path'
        else echo 11; fi
    fi
}
zfs () {
    echo "$*" >> "$state/actions"
    case "$1" in
        get) echo - ;;
        snapshot)
            [ "$mode" != snapshot ] || return 42
            [ "$mode" != snapshot-exists ] || return 1
            echo owned > "$state/snapshot" ;;
        send)
            if [ "$mode" = send ]; then printf partial; return 43; fi
            printf complete ;;
        destroy)
            [ "$mode" != cleanup ] || return 44
            rm "$state/snapshot" ;;
    esac
}
ln () { [ "$mode" != publish ] || return 45; command ln "$@"; }
rm () {
    for last; do :; done
    if [ "$mode" = partial-cleanup ]; then case "$last" in *.partial) return 46 ;; esac; fi
    command rm "$@"
}
failed=0
for mode in snapshot send cleanup publish partial-cleanup image-exists snapshot-exists running query legacy success; do
    state="$workdir/$mode"; iocroot="$state/tree"; mp="$iocroot/jails/$id"
    mkdir -p "$mp/root" "$iocroot/images"
    echo preserved > "$mp/config"; : > "$state/actions"
    image="$iocroot/images/$id-emptyjail-2026-01-01_15.1-RELEASE"
    want=0; status=0
    case "$mode" in snapshot) want=42 ;; send) want=43 ;; cleanup) want=44 ;;
        publish) want=45 ;; partial-cleanup) want=46 ;; query) want=47 ;; legacy) want=48 ;;
        image-exists|snapshot-exists|running) want=1 ;;
    esac
    [ "$mode" != image-exists ] || echo old-image > "$image"
    [ "$mode" != snapshot-exists ] || echo original > "$state/snapshot"
    ( __export "$id" ) > "$state/result.log" 2>&1 || status=$?
    if [ "$status" != "$want" ] || [ "$(cat "$mp/config")" != preserved ]; then
        echo "FAIL: export $mode status=$status expected=$want or changed config"; failed=1; continue
    fi
    case "$mode" in
        success) [ "$(cat "$image")" = complete ] && [ ! -e "$state/snapshot" ] || failed=1 ;;
        image-exists) [ "$(cat "$image")" = old-image ] && [ ! -s "$state/actions" ] || failed=1 ;;
        snapshot-exists) [ "$(cat "$state/snapshot")" = original ] || failed=1 ;;
        send|publish|partial-cleanup)
            [ -f "$image.partial" ] && [ -f "$state/snapshot" ] || failed=1 ;;
        cleanup) [ "$(cat "$image")" = complete ] && [ -f "$state/snapshot" ] || failed=1 ;;
    esac
    if [ "$want" != 0 ] && grep -q 'done!' "$state/result.log"; then
        echo "FAIL: export $mode falsely reported completion"; failed=1; continue
    fi
    echo "PASS: export $mode preserves status and image/snapshot boundaries"
done
exit "$failed"
