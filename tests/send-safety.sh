#!/bin/sh
# Real send orchestration; replace only ZFS/SSH/activation boundaries.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-send-test.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM
jls () { :; }
uuidgen () {
    n=$(cat "${state}/sequence")
    n=$((n + 1)); echo "$n" > "${state}/sequence"
    printf '00000000-0000-0000-0000-%012d\n' "$n"
}
# Keep both requests on the same date, irrespective of a midnight test run.
date () { echo 2026-01-01; }
which () { [ "${buffer}" = yes ]; }
mbuffer () {
    cat
    [ "${fault}" != buffer ] || return 5
}
ssh () {
    if [ "$1" = -o ]; then shift 2; fi
    shift
    case "$*" in
        *'which -s mbuffer'*) [ "$fault" != missing-buffer ] ;;
        exit|*'which -s'*) return 0 ;;
        '/bin/sh -c '*) eval "set -- $*"; ( eval "$3" ) ;;
        *) ( eval "$*" ) ;;
    esac
}
uclcmd () { cat "${state}/active"; }
__activate () {
    pool="$1"
    [ "${fault}" != activate ] || return 8
    echo "$1" > "${state}/active"
}
zfs () {
    case "$1" in
        list)
            [ "$fault" != clean-query ] || return 8
            for f in "${state}/snapshots/"*; do
                [ ! -f "$f" ] || printf '%s@%s\n' "${pool}/iocell" "${f##*/}"
            done
            ;;
        get)
            case "$*" in *mounted*) echo yes ;; *) echo available ;; esac
            ;;
        snapshot)
            [ "${fault}" != snapshot ] || return 9
            for a in "$@"; do snapshot="$a"; done
            file="${state}/snapshots/${snapshot##*@}"
            [ ! -e "$file" ] || return 9
            cp "${state}/current" "$file"
            ;;
        send)
            for a in "$@"; do snapshot="$a"; done
            cat "${state}/snapshots/${snapshot##*@}" || return
            [ "${fault}" != send ] || return 7
            ;;
        receive)
            cat > "${state}/received"
            [ "${fault}" != receive ] || return 6
            cp "${state}/received" "${state}/destination"
            ;;
        destroy)
            for a in "$@"; do target="$a"; done
            case "$target" in
                *@*) rm -f "${state}/snapshots/${target##*@}" ;;
                src/iocell) rm "${state}/source" ;;
                dst/iocell) rm -f "${state}/destination" ;;
                *) return 2 ;;
            esac
            ;;
        mount) [ "${fault}" != mount ] || return 4 ;;
        *) echo "Unexpected ZFS command: $*" >&2; return 2 ;;
    esac
}
failed=0
for mode in local remote buffered ; do
    for fault in none clean clean-query missing-buffer snapshot send receive buffer activate mount ; do
        [ "$mode" = buffered ] || [ "$fault" != buffer ] || continue
        state="${workdir}/${mode}-${fault}"; mkdir -p "$state/snapshots"
        echo 0 > "$state/sequence"; echo original > "$state/source"
        echo first > "$state/current"; buffer=no; OPTIND=1; pool=src
        args=dst
        [ "$mode" = local ] || args='-r -h peer -u root dst'
        case "$fault" in
            clean|clean-query)
                [ "$mode" = local ] || continue
                args='-c dst' ;;
            missing-buffer) [ "$mode" = buffered ] || continue ;;
        esac
        [ "$mode" != buffered ] || buffer=yes
        # Activation/mount faults are local-move cases, not remote sends.
        case "$fault" in
            activate|mount) [ "$mode" = local ] || continue; args='-m dst' ;;
        esac
        status=0
        ( set +e; __send $args ) > "$state/log" 2>&1 || status=$?
        if [ "$fault" = none ] || [ "$fault" = clean ]; then
            if [ "$status" -ne 0 ] || [ "$(cat "$state/destination")" != first ]; then
                echo "FAIL: $mode initial transfer"; cat "$state/log"; failed=1; continue
            fi
            # Each full stream needs a fresh receiver (native refusal tested separately).
            rm -f "$state/destination" "$state/received"
            echo second > "$state/current"; status=0; OPTIND=1
            ( set +e; __send $args ) >> "$state/log" 2>&1 || status=$?
            if [ "$status" -ne 0 ] || [ "$(cat "$state/destination")" != second ]; then
                echo "FAIL: $mode same-day transfer is stale"; failed=1; continue
            fi
        elif [ "$status" -eq 0 ] || [ ! -e "$state/source" ]; then
            echo "FAIL: $mode $fault reports success or removes source"
            failed=1; continue
        fi
        case "$fault" in
            missing-buffer|clean-query)
                if [ -n "$(find "$state/snapshots" -type f -print)" ]; then
                    echo "FAIL: $mode $fault took a snapshot before preflight"; failed=1; continue
                fi ;;
            send|receive|buffer)
                if [ -z "$(find "$state/snapshots" -type f -print)" ] || \
                    ! grep -q 'snapshot retained' "$state/log"; then
                    echo "FAIL: $mode $fault did not retain/report recovery snapshot"; failed=1; continue
                fi ;;
        esac
        echo "PASS: $mode $fault"
    done
done
state="$workdir/move"; mkdir -p "$state/snapshots"; echo 0 > "$state/sequence"
echo original > "$state/source"; echo moved > "$state/current"
pool=src; fault=none; buffer=no; OPTIND=1; status=0
( set +e; __send -m dst ) > "$state/log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ -e "$state/source" ] || \
    [ ! -e "$state/destination" ] || [ "$(cat "$state/destination")" != moved ]; then
    echo 'FAIL: move must retain destination and remove only source'; failed=1
else
    echo 'PASS: move retains destination and removes source'
fi
for kind in local-self remote-same-name; do
    state="$workdir/$kind"; mkdir -p "$state/snapshots"
    echo 0 > "$state/sequence"; echo preserved > "$state/source"
    echo same-name > "$state/current"
    pool=src; fault=none; buffer=no; OPTIND=1; status=0
    args=src
    [ "$kind" = local-self ] || args='-r -h peer -u root src'
    ( set +e; __send $args ) > "$state/log" 2>&1 || status=$?
    if [ "$kind" = local-self ]; then
        if [ "$status" -eq 0 ] || [ ! -e "$state/source" ]; then
            echo 'FAIL: local self-send must be rejected without data loss'
            failed=1; continue
        fi
    elif [ "$status" -ne 0 ] || [ ! -e "$state/destination" ]; then
        echo 'FAIL: remote pools may have the same name as the source'
        failed=1; continue
    fi
    echo "PASS: $kind validation"
done
exit "$failed"
