#!/bin/sh
# Actual jexec failures must survive ALL; pkg format strings stay one argument.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set IOC_TEST_RELEASE to a fetched FreeBSD release}"
# ALL necessarily includes every managed jail; do not disturb other fixtures.
existing=$(zfs list -H -d1 -o name "$IOC_TEST_POOL/iocell/jails")
[ "$(printf '%s\n' "$existing" | wc -l | tr -d ' ')" = 1 ] || {
    ioc_test_error 'exec-pkg-zfs requires an isolated, empty jails namespace'
    exit 1
}
workdir=$(mktemp -d /var/tmp/iocell-exec-pkg.XXXXXX)
echo "Retained exec/pkg logs: $workdir"
first=''; second=''
cleanup () {
    [ -z "$first" ] || sh ./iocell stop "$first" >> "$workdir/stop.log" 2>&1 || :
    [ -z "$second" ] || sh ./iocell stop "$second" >> "$workdir/stop.log" 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
sh ./iocell create "release=$IOC_TEST_RELEASE" tag=exec-pkg-first \
    > "$workdir/create-first.log" 2>&1
sh ./iocell create "release=$IOC_TEST_RELEASE" tag=exec-pkg-second \
    > "$workdir/create-second.log" 2>&1
first=$(sh ./iocell get host_hostuuid exec-pkg-first)
second=$(sh ./iocell get host_hostuuid exec-pkg-second)
sh ./iocell start "$first" "$second" > "$workdir/start.log" 2>&1
printf '%s\n' "$first" "$second" | sort > "$workdir/order"
leading=$(head -n 1 "$workdir/order")
# Every jail receives the identical quoted payload; one fails, another succeeds.
echo 42 > "$IOC_TEST_ROOT/jails/$leading/root/tmp/exec-failure"
status=0
sh ./iocell exec ALL /bin/sh -c '
    printf "%s\n" "$1" > /tmp/exec-payload
    [ ! -f /tmp/exec-failure ] || exit 42
' sh 'literal two words [*]=value' > "$workdir/exec.log" 2>&1 || status=$?
[ "$status" = 42 ]
for id in "$first" "$second"; do
    [ "$(cat "$IOC_TEST_ROOT/jails/$id/root/tmp/exec-payload")" = 'literal two words [*]=value' ]
done
echo 'PASS: actual exec ALL preserves first command failure and runs later targets'
# Package the installed host pkg for a real local add/query, without DNS/network.
pkg create -o "$workdir" pkg > "$workdir/pkg-create.log" 2>&1
package=$(find "$workdir" -name 'pkg-*.pkg' -type f)
[ -n "$package" ]
cp "$package" "$IOC_TEST_ROOT/jails/$first/root/tmp/exec-pkg.pkg"
sh ./iocell pkg "$first" add -f /tmp/exec-pkg.pkg > "$workdir/pkg-install.log" 2>&1
sh ./iocell pkg "$first" query '%n %v' pkg > "$workdir/pkg-query.log" 2>&1
grep -E '^pkg [0-9]' "$workdir/pkg-query.log"
echo 'PASS: actual pkg query preserves a multiword format argument'
