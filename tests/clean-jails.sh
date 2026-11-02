#!/bin/sh
# Jail cleanup must not remove template aliases or cascade outside its tree.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-clean-jails.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; _force=1
__clean_snapshots () { return 0; }
__stop_jail_all () { [ "$fault" != stop ] || return 43; }
zfs () {
    case "$*" in
        'list -H -d1 -t filesystem -o name,mountpoint tank/iocell/jails')
            [ "$fault" != query ] || return 42
            printf 'tank/iocell/jails\t%s/jails\ntank/iocell/jails/first\t%s/jails/first\n' "$iocroot" "$iocroot" ;;
        'destroy -rf tank/iocell/jails'|'destroy -rRf tank/iocell/jails')
            [ "$fault" != destroy ] || return 44
            if [ "$fault" = dependent ]; then
                [ "$2" = -rRf ] || return 45
                rm -f "$iocroot/templates/kept/data"
            fi
            rm -rf "$iocroot/jails" ;;
        *) echo "unexpected ZFS call: $*" >&2; return 99 ;;
    esac
}
failed=0
for fault in none query stop destroy dependent; do
    iocroot="$workdir/$fault"
    mkdir -p "$iocroot/jails/first" "$iocroot/templates/kept" "$iocroot/tags"
    echo jail > "$iocroot/jails/first/data"
    echo template > "$iocroot/templates/kept/data"
    ln -s "$iocroot/jails/first" "$iocroot/tags/jail"
    ln -s ../jails/first "$iocroot/tags/jail-relative"
    ln -s "$iocroot/templates/kept" "$iocroot/tags/template"
    status=0; want=0
    case "$fault" in query) want=42 ;; stop) want=43 ;; destroy) want=44 ;; dependent) want=45 ;; esac
    ( __clean_jails ) > "$iocroot/result.log" 2>&1 || status=$?
    if [ "$status" != "$want" ] ||
        [ ! -L "$iocroot/tags/template" ] ||
        [ "$(cat "$iocroot/templates/kept/data" 2>/dev/null)" != template ]; then
        echo "FAIL: clean-j $fault lost status, template data or alias"; failed=1
    elif [ "$want" = 0 ]; then
        if [ -e "$iocroot/jails" ] || [ -L "$iocroot/tags/jail" ] ||
            [ -L "$iocroot/tags/jail-relative" ]; then
            echo 'FAIL: successful clean-j retained jail data/aliases'; failed=1
        else echo 'PASS: clean-j removes only destroyed jail aliases'; fi
    elif [ ! -L "$iocroot/tags/jail" ] ||
        [ "$(cat "$iocroot/jails/first/data" 2>/dev/null)" != jail ]; then
        echo "FAIL: clean-j $fault changed preserved jail state"; failed=1
    else echo "PASS: clean-j $fault preserves data and namespace"; fi
done
exit "$failed"
