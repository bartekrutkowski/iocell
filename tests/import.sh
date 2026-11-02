#!/bin/sh
# Execute the real importer; replace only the ZFS receive boundary.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-image
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-import.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM
pool=tank
release=15.1-RELEASE
uuid=11111111-1111-1111-1111-111111111111
__find_jail () { echo "tank/iocell/jails/$uuid"; }
__check_name () { echo "$uuid"; }
__get_jail_prop () { echo existing-jail; }
zfs () {
    if [ "$1" != recv ] || [ "$2" != -d ] || [ "$3" != tank ] || \
        [ "$#" -ne 3 ]; then
        echo 'Unexpected/destructive ZFS arguments' >&2
        return 99
    fi
    printf '%s\n' invoked > "$state/receive-called"
    input=$(cat) || return $?
    case "$input" in
        valid-stream)
            mkdir -p "$iocroot/jails/$uuid/root"
            echo restored > "$iocroot/jails/$uuid/root/marker"
            ;;
        partial-stream)
            mkdir -p "$iocroot/jails/$uuid/root"
            echo incomplete > "$iocroot/jails/$uuid/root/partial"
            echo 'fixture receive: truncated stream' >&2
            return 8
            ;;
        *) echo 'fixture receive: invalid stream' >&2; return 7 ;;
    esac
}
failed=0
for label in valid short-prefix corrupt truncated existing ambiguous missing properties empty-raw partial literal-prefix spaced missing-release; do
    state="$workdir/$label"; iocroot="$state/iocell"
    [ "$label" != spaced ] || iocroot="$state/iocell with spaces"
    mkdir -p "$iocroot/images" "$iocroot/jails" "$iocroot/releases/$release"
    image="$iocroot/images/$uuid-basejail-2026-01-01_$release"
    echo valid-stream > "$image"
    name="$uuid"; want=0
    case "$label" in
        short-prefix) name=11111111 ;;
        corrupt) echo invalid-stream > "$image"; want=7 ;;
        truncated) echo partial-stream > "$image"; want=8 ;;
        existing)
            mkdir -p "$iocroot/jails/$uuid/root"
            echo original > "$iocroot/jails/$uuid/root/marker"
            want=1
            ;;
        ambiguous) cp "$image" "$image-other"; want=1 ;;
        missing) rm "$image"; want=1 ;;
        properties) want=1 ;;
        empty-raw) new="$iocroot/images/$uuid-emptyjail-2026-01-01_$release"
            mv "$image" "$new"; image="$new" ;;
        partial) mv "$image" "$image.partial"; image="$image.partial"; want=1 ;;
        literal-prefix) name="$uuid*"; want=1 ;;
        missing-release) rmdir "$iocroot/releases/$release"; want=1 ;;
    esac
    [ ! -f "$image" ] || cp "$image" "$state/image-before"
    status=0
    set -- "$name"
    [ "$label" != properties ] || set -- "$name" notes=restored
    ( set +e; __import "$@" ) > "$state/log" 2>&1 || status=$?
    if [ "$status" -ne "$want" ]; then
        echo "FAIL: $label status $status, expected $want"
        cat "$state/log"; failed=1; continue
    fi
    if [ "$want" = 0 ]; then
        [ "$(cat "$iocroot/jails/$uuid/root/marker")" = restored ] || {
            echo "FAIL: $label content was not restored"; failed=1; continue;
        }
        grep -q 'done!' "$state/log" || { failed=1; continue; }
    else
        if grep -q 'done!' "$state/log"; then
            echo "FAIL: $label printed success after failure"; failed=1; continue
        fi
        case "$label" in
            corrupt|truncated)
                grep -q 'fixture receive:' "$state/log" || {
                    echo "FAIL: $label lost receive diagnostics"; failed=1; continue;
                }
                ;;
            *)
                [ ! -e "$state/receive-called" ] || {
                    echo "FAIL: $label attempted a receive"; failed=1; continue;
                }
                ;;
        esac
    fi
    if [ "$label" = existing ]; then
        [ "$(cat "$iocroot/jails/$uuid/root/marker")" = original ] || {
            failed=1; continue;
        }
    fi
    if [ "$label" = truncated ]; then
        [ "$(cat "$iocroot/jails/$uuid/root/partial")" = incomplete ] || {
            echo 'FAIL: partial receive was silently deleted'; failed=1; continue;
        }
    fi
    if [ -f "$state/image-before" ]; then
        cmp -s "$image" "$state/image-before" || { failed=1; continue; }
    fi
    echo "PASS: import $label"
done
exit "$failed"
