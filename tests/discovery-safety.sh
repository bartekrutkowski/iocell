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
uuid=a1111111-b111-c111-d111-e11111111111
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
            if [ "${extra_candidates:-no}" = yes ]; then
                printf '%s\n' "$broken" "$unconfigured" "$unnamed"
            fi
            printf '%s\n' "$jail" "$jail/root" "$jail/backup" "$template"
            ;;
        get)
            for a in "$@"; do dataset="$a"; done
            case "$*" in
                *' mountpoint '*) echo "$iocroot/${dataset#tank/iocell/}" ;;
                *' origin '*) echo - ;;
                *' org.freebsd.iocell:host_hostuuid '*)
                    [ "${legacy_identity:-yes}" != no ] && echo "$uuid" || echo - ;;
                *' org.freebsd.iocell:tag '*) echo legacy-broken ;;
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
tr () {
    [ "$*" != '[:upper:] [:lower:]' ] || echo fold >> "$workdir/casefold.trace"
    command tr "$@"
}
: > "$workdir/casefold.trace"
__find_jail original > "$workdir/casefold.out"
if [ "$(wc -l < "$workdir/casefold.trace" | command tr -d ' ')" -gt 1 ]; then
    echo 'FAIL: lookup case-folds separately for every candidate'; failed=1
else echo 'PASS: lookup case-folding has constant subprocess cost'; fi
status=0
( set +e; __find_jail database-template ) > "$workdir/find" 2> "$workdir/error" || status=$?
if [ "$status" -ne 0 ] || [ "$(cat "$workdir/find")" != "$template" ]; then
    echo 'FAIL: valid template names must not be filtered by substrings'; failed=1
else
    echo 'PASS: template names containing database are discoverable'
fi
for name in A1111111-B111-C111-D111-E11111111111 DATABASE-TEMPLATE; do
    want="$jail"; [ "$name" != DATABASE-TEMPLATE ] || want="$template"
    status=0
    ( __find_jail "$name" ) > "$workdir/case.out" 2> "$workdir/case.err" || status=$?
    if [ "$status" != 0 ] || [ "$(cat "$workdir/case.out")" != "$want" ]; then
        echo "FAIL: case-folded dataset identity $name was not found"; failed=1
    else echo "PASS: case-folded dataset identity $name"; fi
done
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
# A newly incomplete dataset must not be fabricated into a legacy jail.
rm "$iocroot/jails/$uuid/config"
legacy_identity=no; status=0
( __dump_config "$uuid" ) > "$workdir/no-legacy.log" 2>&1 || status=$?
if [ "$status" = 0 ] || [ -e "$iocroot/jails/$uuid/config" ]; then
    echo 'FAIL: missing native legacy identity fabricated a config'; failed=1
else
    echo 'PASS: unconfigured non-legacy dataset is not fabricated'
fi
legacy_identity=yes
echo original > "$iocroot/jails/$uuid/config"
broken=tank/iocell/jails/33333333-3333-3333-3333-333333333333
unconfigured=tank/iocell/templates/unconfigured-template
unnamed=tank/iocell/jails/non-uuid-dataset
mkdir -p "$iocroot/jails/${broken##*/}" "$iocroot/templates/unconfigured-template" \
    "$iocroot/jails/non-uuid-dataset"
extra_candidates=yes
# Exercise an exiting legacy backend, not merely a returned error.
__dump_config () { __die "fixture migration failure: $1"; }
status=0
( __find_jail ALL ) > "$workdir/all-broken.out" 2> "$workdir/all-broken.err" || status=$?
if [ "$status" != 0 ] || ! grep -Fx "$jail" "$workdir/all-broken.out" || \
    ! grep -Fx "$broken" "$workdir/all-broken.out" || \
    ! grep -Fx "$unconfigured" "$workdir/all-broken.out" || \
    ! grep -Fx "$unnamed" "$workdir/all-broken.out" || [ ! -s "$workdir/all-broken.err" ]; then
    echo 'FAIL: one failed/unconfigured identity truncated ALL or disappeared'; failed=1
else
    echo 'PASS: ALL reports unconfigured identities and continues after failed migration'
fi
status=0
( __find_jail unconfigured-template ) > "$workdir/no-config.out" \
    2> "$workdir/no-config.err" || status=$?
if [ "$status" != 0 ] || [ "$(cat "$workdir/no-config.out")" != "$unconfigured" ] || \
    [ ! -s "$workdir/no-config.err" ]; then
    echo 'FAIL: named unconfigured template was hidden'; failed=1
else
    echo 'PASS: named unconfigured template remains discoverable with a diagnostic'
fi
exit "$failed"
