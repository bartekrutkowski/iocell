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
__check_name () { echo fixture; }
__get_jail_prop () { case "$1" in origin) echo - ;; *) echo fixture ;; esac; }
zfs () {
    case "$1" in
        list)
            [ "$fault" != list ] || return 7
            printf '%s\n' tank/iocell/jails/fixture tank/iocell/jails/fixture/root
            ;;
        get)
            [ "$fault" != origin ] || return 8
            if [ "$dependent" = yes ]; then
                printf '%s\t%s\n' tank/iocell/jails/fixture/root \
                    tank/iocell/templates/template/root@saved
            else
                printf '%s\t-\n' tank/iocell/jails/fixture/root
            fi
            ;;
        destroy)
            [ "$fault" != destroy ] || return 9
            [ "$fault" != race ] || dependent=yes
            if [ "$dependent" = yes ]; then
                case "$2" in
                    *R*) rm -f "$state/clone" ;;
                    *) return 10 ;;
                esac
            fi
            rm "$state/template"
            ;;
        *) return 1 ;;
    esac
}
failed=0
for label in dependent clear forced destroy-failure origin-failure race ; do
    state="$workdir/$label"; mkdir "$state"
    echo data > "$state/clone"; echo source > "$state/template"
    dependent=no; _force=0; fault=none
    case "$label" in
        dependent) dependent=yes ;;
        forced) dependent=yes; _force=1 ;;
        destroy-failure) fault=destroy ;;
        origin-failure) fault=origin ;;
        race) fault=race ;;
    esac
    status=0
    args=-t
    [ "$_force" != 1 ] || args='-f -t'
    ( set +e; OPTIND=1; printf 'y\n' | __clean $args ) > "$state/log" 2>&1 || status=$?
    case "$label" in
        clear|forced)
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
    echo "PASS: $label template cleanup"
done
exit "$failed"
