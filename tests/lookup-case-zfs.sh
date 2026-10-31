#!/bin/sh
# Fold dataset identities, not literal config tags, and refuse ambiguous names.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-lookup-case.XXXXXX)
p=$(ioc_test_pool_name ioccase)
echo "Retained lookup logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint="$workdir/tree" "$p" "$workdir/pool.vdev"
u=$(uuidgen); ds="$p/iocell/jails/$u"
zfs create -p "$ds"
zfs create -p "$p/iocell/templates/Database-Template"
mp=$(zfs get -H -o value mountpoint "$ds")
printf 'tag="MiXeD"; host_hostuuid="%s";\n' "$u" > "$mp/config"
tmp="$workdir/tree/iocell/templates/Database-Template"
echo 'tag="Database-Template";' > "$tmp/config"
cp "$mp/config" "$workdir/config-before"
guid=$(zfs get -H -o value guid "$ds")
find_name () (
    . ./lib/ioc-common
    . ./lib/ioc-info
    pool="$p"
    __find_jail "$1"
)
upper=$(printf '%s' "$u" | tr '[:lower:]' '[:upper:]')
[ "$(find_name "$upper")" = "$ds" ]
echo 'PASS: native uppercase UUID resolves its canonical dataset'
[ "$(find_name database-template)" = "$p/iocell/templates/Database-Template" ]
echo 'PASS: native template dataset names are case-insensitive'
[ "$(find_name MiXeD)" = "$ds" ]
if find_name mixed > "$workdir/literal.out" 2> "$workdir/literal.err"; then exit 1; fi
echo 'PASS: native config tags retain literal case-sensitive lookup'
zfs create "$p/iocell/templates/database-template"
echo 'tag="database-template";' > "$workdir/tree/iocell/templates/database-template/config"
if find_name DATABASE-TEMPLATE > "$workdir/ambiguous.out" 2> "$workdir/ambiguous.err"; then exit 1; fi
grep -q 'multiple jails' "$workdir/ambiguous.err"
cmp "$mp/config" "$workdir/config-before"
[ "$(zfs get -H -o value guid "$ds")" = "$guid" ]
echo 'PASS: native case-folded ambiguity refuses without changing config or GUID'
