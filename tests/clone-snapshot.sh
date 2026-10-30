#!/bin/sh
# Clone orchestration: snapshot preflight, root/data bytes and failure boundaries.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-clone.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
trap 'exit 1' HUP INT TERM
pool=tank
uuid=11111111-1111-1111-1111-111111111111
source_uuid=22222222-2222-2222-2222-222222222222
source_dataset="tank/iocell/jails/$source_uuid"
target_dataset="tank/iocell/jails/$uuid"
host_hostname="$uuid"; start=''
__find_jail () { [ "$fault" != find ] || return 7; echo "$source_dataset"; }
__check_name () { echo "$source_uuid"; }
__configure_jail () {
    [ "$fault" != config ] || return 44
    echo generated > "$iocroot/jails/$uuid/config"
}
__link_tag () { echo link >> "$trace"; [ "$fault" != link ] || return 45; }
__set_jail_prop () { echo "property $*" >> "$trace"; }
__hack88_mount () { :; }
__resolv_conf () { echo 'nameserver 127.0.0.1'; }
zfs () {
    echo "zfs $*" >> "$trace"
    case "$1" in
        list)
            case " $* " in
                *' snapshot '*)
                    for arg in "$@"; do snapshot="$arg"; done
                    kind=${snapshot%@*}; kind=${kind##*/}
                    [ -f "$state/snapshots/$kind-${snapshot##*@}" ] || return 1
                    echo "$snapshot"
                    ;;
                *)
                    [ "$fault" != list ] || return 8
                    printf '%s\n' "$source_dataset" "$source_dataset/root"
                    [ "$data" != yes ] || echo "$source_dataset/data"
                    ;;
            esac
            ;;
        snapshot)
            [ "$fault" != snapshot ] || return 9
            for arg in "$@"; do snapshot="$arg"; done
            cp "$state/live-root" "$state/snapshots/root-${snapshot##*@}"
            if [ "$data" = yes ]; then
                case " $* " in
                    *' -r '*) cp "$state/live-data" "$state/snapshots/data-${snapshot##*@}" ;;
                esac
            fi
            ;;
        create) mkdir -p "$iocroot/jails/$uuid" ;;
        clone)
            for arg in "$@"; do previous=${destination:-}; destination="$arg"; done
            kind=${destination##*/}
            [ "$fault" != "clone-$kind" ] || {
                [ "$kind" != root ] || return 42
                return 43
            }
            [ -f "$state/snapshots/$kind-${previous##*@}" ] || return 1
            mkdir -p "$iocroot/jails/$uuid/$kind"
            cp "$state/snapshots/$kind-${previous##*@}" "$iocroot/jails/$uuid/$kind/marker"
            if [ "$kind" = root ]; then
                mkdir -p "$iocroot/jails/$uuid/root/etc"
                echo 'hostname="original"' > "$iocroot/jails/$uuid/root/etc/rc.conf"
            fi
            ;;
        *) echo "Unexpected ZFS operation: $*" >&2; return 99 ;;
    esac
}
failed=0
for label in explicit automatic explicit-data automatic-data missing-root missing-data \
    list-failure snapshot-failure root-failure data-failure config-failure \
    link-failure find-failure; do
    state="$workdir/$label"; iocroot="$state/iocell"; trace="$state/trace"
    mkdir -p "$state/snapshots" "$iocroot/jails"
    : > "$trace"; fault=none; data=no; argument=example@saved; want=0
    echo live-root > "$state/live-root"; echo live-data > "$state/live-data"
    echo saved-root > "$state/snapshots/root-saved"
    case "$label" in
        automatic) argument=example ;;
        explicit-data) data=yes; echo saved-data > "$state/snapshots/data-saved" ;;
        automatic-data) data=yes; argument=example ;;
        missing-root) rm "$state/snapshots/root-saved"; want=1 ;;
        missing-data) data=yes; want=1 ;;
        list-failure) fault=list; want=8 ;;
        snapshot-failure) argument=example; fault=snapshot; want=9 ;;
        root-failure) fault=clone-root; want=42 ;;
        data-failure) data=yes; fault=clone-data; want=43
            echo saved-data > "$state/snapshots/data-saved" ;;
        config-failure) fault=config; want=44 ;;
        link-failure) fault=link; want=45 ;;
        find-failure) fault=find; want=7 ;;
    esac
    status=0
    ( set +e; __clone_jail "$argument" ) > "$state/log" 2>&1 || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: clone $label status $status, expected $want"
        cat "$state/log"; failed=1; continue
    fi
    if [ "$want" = 0 ]; then
        expected_root=saved-root; expected_data=saved-data
        case "$label" in automatic*) expected_root=live-root; expected_data=live-data ;; esac
        [ "$(cat "$iocroot/jails/$uuid/root/marker")" = "$expected_root" ] || {
            echo "FAIL: clone $label lost root content"; failed=1; continue;
        }
        if [ "$data" = yes ]; then
            [ "$(cat "$iocroot/jails/$uuid/data/marker")" = "$expected_data" ] || {
                echo "FAIL: clone $label lost delegated data"; failed=1; continue;
            }
        fi
        grep -q 'Successfully created' "$state/log" || { failed=1; continue; }
    else
        if grep -q 'Successfully created' "$state/log"; then
            echo "FAIL: clone $label printed success"; failed=1; continue
        fi
        case "$label" in
            missing-root|missing-data|list-failure|snapshot-failure|find-failure)
                [ ! -d "$iocroot/jails/$uuid" ] || {
                    echo "FAIL: clone $label created a target before preflight"; failed=1; continue;
                } ;;
        esac
        if [ "$label" != link-failure ] && grep -Eq '^(link($| )|property )' "$trace"; then
            echo "FAIL: clone $label published metadata after failure"; failed=1; continue
        fi
    fi
    echo "PASS: clone $label"
done
exit "$failed"
