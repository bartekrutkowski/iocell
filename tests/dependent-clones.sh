#!/bin/sh
# Native origins, including outside the jail namespace and delegated data.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
pool=tank
uuid=11111111-1111-1111-1111-111111111111
source="tank/iocell/jails/$uuid"
__check_name () { echo "$uuid"; }
__get_jail_prop () { echo fixture; }
zfs () {
    [ "$label" != query-failure ] || return 8
    case "$1" in
        list)
            printf '%s\n' "$source" "$source/root"
            [ "$label" != internal ] || echo "$source/backup"
            ;;
        get)
            case " $* " in
                *' name,value '*)
                    printf '%s\t%s\n' "$source/root" -
                    case "$label" in
                        internal) printf '%s\t%s\n' "$source/backup" "$source/root@saved" ;;
                        root-external) printf '%s\t%s\n' tank/outside-root "$source/root@saved" ;;
                        data-external) printf '%s\t%s\n' tank/outside-data "$source/data@saved" ;;
                        unrelated) printf '%s\t%s\n' tank/outside "$source-other/root@saved" ;;
                    esac
                    ;;
                *) for last; do :; done
                    if [ "$last" = "$source/backup" ]; then echo "$source/root@saved"
                    else echo -; fi ;;
            esac ;;
    esac
}
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-dependents.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
failed=0
for label in none internal root-external data-external unrelated query-failure; do
    want=0
    case "$label" in *-external) want=1 ;; query-failure) want=8 ;; esac
    status=0
    ( __check_children "$uuid" "$source" ) > "$workdir/$label.out" \
        2> "$workdir/$label.err" || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: dependency $label status=$status expected=$want"; failed=1; continue
    fi
    if [ "$want" != 0 ] && [ ! -s "$workdir/$label.err" ]; then
        echo "FAIL: dependency $label has no diagnostic"; failed=1; continue
    fi
    echo "PASS: dependency $label"
done
exit "$failed"
