#!/bin/sh
# Discovery must not reinterpret nested datasets as legacy parent jails.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-discovery.XXXXXX")
trap 'if [ "${failed:-1}" = 0 ]; then rm -rf "${workdir}"; else echo "Retained: ${workdir}" >&2; fi' EXIT
trap 'exit 1' HUP INT TERM
pool=tank
id () { if [ "$1" = -un ]; then echo root; else command id "$@"; fi; }
iocroot="$workdir/iocell"
uuid=11111111-1111-1111-1111-111111111111
jail="tank/iocell/jails/$uuid"
template=tank/iocell/templates/database-template
mkdir -p "$iocroot/jails/$uuid/backup" "$iocroot/templates/database-template"
echo original > "$iocroot/jails/$uuid/config"
echo database-template > "$iocroot/templates/database-template/config"
__configure_jail () { echo migrated > "$4/config"; }
__get_jail_prop () { echo basejail; }
uclcmd () { cat "$3"; }
zfs () {
    case "$1" in
        list)
            printf '%s\n' "$jail" "$jail/root" "$jail/backup" "$template"
            ;;
        get)
            for a in "$@"; do dataset="$a"; done
            case "$*" in
                *' mountpoint '*) echo "$iocroot/${dataset#tank/iocell/}" ;;
                *' origin '*) echo - ;;
                *' property,value all '*) : ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}
failed=0
for name in ALL original ; do
    echo original > "$iocroot/jails/$uuid/config"
    status=0
    ( set +e; __find_jail "$name" ) > "$workdir/find-$name" 2> "$workdir/error-$name" || status=$?
    if [ "$status" -ne 0 ] || [ "$(cat "$iocroot/jails/$uuid/config")" != original ]; then
        echo "FAIL: discovery $name overwrites parent config"; failed=1
    else
        echo "PASS: discovery $name preserves parent config"
    fi
done
status=0
( set +e; __find_jail database-template ) > "$workdir/find" 2> "$workdir/error" || status=$?
if [ "$status" -ne 0 ] || [ "$(cat "$workdir/find")" != "$template" ]; then
    echo 'FAIL: valid template names must not be filtered by substrings'; failed=1
else
    echo 'PASS: template names containing database are discoverable'
fi
echo original > "$iocroot/jails/$uuid/config"
( set +e; __dump_config "$uuid" ) > "$workdir/dump" 2>&1 || :
if [ "$(cat "$iocroot/jails/$uuid/config")" != original ]; then
    echo 'FAIL: migration overwrites existing config'; failed=1
else
    echo 'PASS: migration preserves existing config'
fi
rm "$iocroot/jails/$uuid/config"
status=0
( set +e; __dump_config "$uuid" ) > "$workdir/dump" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ "$(cat "$iocroot/jails/$uuid/config")" != migrated ]; then
    echo 'FAIL: genuine missing legacy config is not migrated'; failed=1
else
    echo 'PASS: genuine missing legacy config is migrated'
fi
exit "$failed"
