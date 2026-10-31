#!/bin/sh
# Keep the real cleanup implementation and real file effects of destruction.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-clean-template.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM
pool=tank
zfs () {
    case "$1" in
        get)
            [ "$fault" != origin ] || return 8
            if [ "$dependent" = yes ]; then
                printf '%s\t%s\n' tank/iocell/jails/fixture/root \
                    tank/iocell/templates/template/root@saved
            elif [ "$dependent" = internal ]; then
                printf '%s\t%s\n' tank/iocell/templates/inner/root \
                    tank/iocell/templates/template/root@saved
            else
                printf '%s\t-\n' tank/iocell/jails/fixture/root
            fi
            ;;
        destroy)
            if [ "$2" = -nvrRf ]; then
                printf '%s\n' 'would destroy tank/iocell/jails/fixture/root'
                return 0
            fi
            [ "$fault" != destroy ] || return 9
            [ "$fault" != race ] || dependent=yes
            if [ "$dependent" = yes ]; then
                case "$2" in
                    *R*) rm -f "$state/clone" ;;
                    *) return 10 ;;
                esac
            fi
            [ "$dependent" != internal ] || rm "$state/clone"
            rm "$state/template"
            ;;
        *) return 1 ;;
    esac
}
failed=0
for label in dependent clear internal forced destroy-failure origin-failure race ; do
    state="$workdir/$label"; mkdir "$state"
    echo data > "$state/clone"; echo source > "$state/template"
    dependent=no; _force=0; fault=none
    case "$label" in
        dependent) dependent=yes ;;
        forced) dependent=yes; _force=1 ;;
        internal) dependent=internal ;;
        destroy-failure) fault=destroy ;;
        origin-failure) fault=origin ;;
        race) fault=race ;;
    esac
    status=0
    args=-t
    [ "$_force" != 1 ] || args='-f -t'
    ( set +e; OPTIND=1; printf 'y\n' | __clean $args ) > "$state/log" 2>&1 || status=$?
    case "$label" in
        clear|internal|forced)
            if [ "$status" -ne 0 ] || [ -e "$state/template" ]; then
                echo "FAIL: $label cleanup did not succeed"; failed=1; continue
            fi
            ;;
        *)
            if [ "$status" -eq 0 ] || [ ! -e "$state/template" ] || [ ! -e "$state/clone" ]; then
                echo "FAIL: $label cleanup reports success or loses data"; failed=1; continue
            fi
            ;;
    esac
    if [ "$label" = forced ] && ! grep -F 'tank/iocell/jails/fixture/root' "$state/log" >/dev/null; then
        echo 'FAIL: force cleanup did not list its external clone' >&2; failed=1; continue
    fi
    if [ "$label" = internal ] && [ -e "$state/clone" ]; then
        echo 'FAIL: internal clone was not part of recursive removal' >&2; failed=1; continue
    fi
    echo "PASS: $label template cleanup"
done
exit "$failed"
