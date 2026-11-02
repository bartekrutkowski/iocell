#!/bin/sh
# Select the mounted dataset, never a plausible /iocell directory or altroot.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-bootstrap.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank
CONF_NET=''; CONF_JAIL=''; CONF_RCTL=''; CONF_CUSTOM=pool
CONF_SYNC=''; CONF_FTP=''; CONF_GIT=''
id () { echo "$actor"; }
zpool () { printf 'tank\taltroot\t%s/guessed\tlocal\n' "$state"; }
touch () { [ "$1" = /etc/devfs.rules ] || command touch "$@"; }
zfs () {
    case "$1" in
        list) [ "$mode" != query ] || return 42; command cat "$state/datasets" ;;
        get)
            case "$*" in
                *' mounted '*) [ "$mode" != mount ] && echo yes || echo no ;;
                *' creation '*) for ds; do :; done
                    grep -Fx "$ds" "$state/datasets" >/dev/null ;;
                *) return 99 ;;
            esac ;;
        create)
            for ds; do :; done
            printf '%s\n' "$ds" >> "$state/datasets"
            mkdir -p "$wanted/${ds#tank/iocell/}"
            ;;
        mount)
            if [ "$#" = 1 ]; then printf 'tank/iocell  %s\n' "$wanted"; return 0; fi
            if [ "${2:-}" = -a ]; then echo global > "$state/global-mount"; return 99; fi
            [ "$mode" != mount ] || return 43 ;;
        destroy) [ "$mode" != legacy ] || return 44 ;;
        *) return 99 ;;
    esac
}
mount () {
    encoded=$(printf '%s' "$wanted" | sed 's/ /\\040/g')
    printf 'tank/iocell\t%s\tzfs\trw\t0\t0\n' "$encoded"
}
failed=0
for mode in selected quoted query mount missing legacy readonly; do
    state="$workdir/$mode"; wanted="$state/actual"; actor=root
    [ "$mode" != quoted ] || wanted="$state/actual quote'&[ab] \$(touch injected)"
    old="$state/old-root"; LIB="$state/lib with spaces"
    mkdir -p "$wanted" "$old" "$LIB" "$state/guessed/iocell"
    echo old-selector > "$old/.default"
    echo selected-default > "$wanted/.default"
    printf 'iocroot=%s\nsentinel=original\n' "$old" > "$LIB/ioc-globals"
    iocroot="$old"
    [ "$mode" != readonly ] || { iocroot="$wanted"; actor=nobody; }
    printf '%s\n' tank tank/iocell tank/iocell/download tank/iocell/jails \
        tank/iocell/releases tank/iocell/templates > "$state/datasets"
    if [ "$mode" = missing ]; then
        grep -v templates "$state/datasets" > "$state/datasets.new"
        mv "$state/datasets.new" "$state/datasets"
    elif [ "$mode" = legacy ]; then
        echo tank/iocell/.defaults >> "$state/datasets"
        rm "$wanted/.default"; mkdir "$wanted/.defaults"
        echo retained > "$wanted/.defaults/canary"
    fi
    status=0; want=0
    case "$mode" in query) want=42 ;; mount) want=43 ;; legacy) want=44 ;; esac
    (
        cd "$state"
        __check_filesystems || exit $?
        printf '%s\n' "$iocroot" > "$state/result"
    ) > "$state/log" 2>&1 || status=$?
    if [ "$status" != "$want" ] || [ -e "$state/global-mount" ] ||
        [ "$(cat "$old/.default")" != old-selector ]; then
        echo "FAIL: bootstrap $mode lost status, selected wrong defaults or mounted other pools"; failed=1
    elif [ "$want" = 0 ]; then
        if [ "$(cat "$state/result")" != "$wanted" ] ||
            [ "$(cat "$wanted/.default")" != selected-default ]; then
            echo "FAIL: bootstrap $mode did not use the mounted dataset root"; failed=1
        elif [ "$mode" != readonly ]; then
            saved=$(cd "$state"; sh -c '. "$1"; printf "%s" "$iocroot"' sh "$LIB/ioc-globals")
            if [ "$saved" != "$wanted" ] || [ -e "$state/injected" ]; then
                echo 'FAIL: bootstrap did not persist root as literal shell data'; failed=1
            else echo "PASS: bootstrap $mode selects and persists actual mounted root"; fi
        else echo 'PASS: readonly bootstrap needs no selector rewrite'; fi
    elif [ "$mode" = legacy ] && [ "$(cat "$wanted/.defaults/canary")" != retained ]; then
        echo 'FAIL: failed legacy-default cleanup erased retained data'; failed=1
    else echo "PASS: bootstrap $mode preserves failure and existing data"; fi
done
exit "$failed"
