#!/bin/sh
# An empty failed-fetch tree may be removed, never snapshots or other contents.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-git
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-plugin-release.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; release=15.1-RELEASE; ds=tank/iocell/releases/15.1-RELEASE
zfs () {
    case "$*" in
        "get -H -o value mountpoint $ds") echo "$iocroot/releases/$release" ;;
        "get -H -o value mounted $ds") echo yes ;;
        "get -H -o value mountpoint $ds/root") echo "$iocroot/releases/$release/root" ;;
        "get -H -o value mounted $ds/root")
            [ "$mode" = unmounted ] && echo no || echo yes ;;
        "list -rH -t filesystem,volume,snapshot -o name $ds")
            [ "$mode" != query ] || return 42
            printf '%s\n' "$ds"
            [ "$mode" = incomplete ] || printf '%s\n' "$ds/root"
            case "$mode" in snapshot) echo "$ds/root@saved" ;; child) echo "$ds/other" ;; esac ;;
        "destroy $ds/root")
            echo "$*" >> "$state/actions"
            [ "$mode" != destroy-failure ] || return 43
            rmdir "$iocroot/releases/$release/root" ;;
        "destroy $ds") echo "$*" >> "$state/actions"; rmdir "$iocroot/releases/$release" ;;
        *) echo "unexpected zfs: $*" >&2; return 99 ;;
    esac
}
failed=0
for mode in empty snapshot child data parent-data unmounted query destroy-failure incomplete; do
    state="$workdir/$mode"; iocroot="$state/tree"
    mkdir -p "$iocroot/releases/$release/root"; : > "$state/actions"
    case "$mode" in data) echo keep > "$iocroot/releases/$release/root/canary" ;;
        parent-data) echo keep > "$iocroot/releases/$release/canary" ;; esac
    want=1; case "$mode" in empty) want=0 ;; query) want=42 ;; destroy-failure) want=43 ;; esac
    status=0
    ( __remove_empty_plugin_release "$release" ) > "$state/log" 2>&1 || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: plugin release $mode status=$status expected=$want"; failed=1; continue
    fi
    if [ "$mode" = incomplete ] && [ ! -s "$state/log" ]; then
        echo 'FAIL: incomplete plugin release layout has no diagnostic'; failed=1; continue
    fi
    if [ "$mode" = empty ]; then
        printf 'destroy %s/root\ndestroy %s\n' "$ds" "$ds" > "$state/expected"
        cmp "$state/actions" "$state/expected" || exit 1
        [ ! -d "$iocroot/releases/$release" ] || exit 1
    elif [ "$mode" != destroy-failure ] && [ -s "$state/actions" ]; then
        echo "FAIL: plugin release $mode destroyed protected state"; failed=1; continue
    else [ -d "$iocroot/releases/$release/root" ] || exit 1; fi
    echo "PASS: plugin release cleanup $mode"
done
exit "$failed"
