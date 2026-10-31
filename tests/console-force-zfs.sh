#!/bin/sh
# Real forced startup; only the interactive login is replaced.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set a fetched release}"
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
workdir=$(mktemp -d /var/tmp/iocell-console-zfs.XXXXXX)
echo "Retained forced-console logs: $workdir"
tag="console-force-$(uuidgen)"
iocell create "release=$IOC_TEST_RELEASE" "tag=$tag" vnet=off ip4_addr=none \
    ip6_addr=none > "$workdir/create.log" 2>&1
uuid=$(iocell get host_hostuuid "$tag")
cleanup () {
    iocell stop "$tag" >/dev/null 2>&1 || :
    jail -r "ioc-$tag" >/dev/null 2>&1 || :
    jail -r "ioc-$uuid" >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$workdir/bin"
real_jexec=$(command -v jexec)
cat > "$workdir/bin/jexec" <<WRAPPER
#!/bin/sh
if [ "\${2:-}" = login ]; then
    jls -j "\$1" jid >/dev/null || exit 43
    printf '%s\n' "\$*" >> "$workdir/login.trace"
    exit 0
fi
exec "$real_jexec" "\$@"
WRAPPER
chmod +x "$workdir/bin/jexec"
[ "$(iocell get state "$uuid")" = down ]
PATH="$workdir/bin:$PATH" iocell console -f "$tag" > "$workdir/forced.log" 2>&1
[ "$(iocell get state "$uuid")" = up ]
grep -Fx "ioc-$uuid login -f root" "$workdir/login.trace"
jid=$(jls -j "ioc-$uuid" jid)
echo 'PASS: native forced console starts the resolved jail before login'
PATH="$workdir/bin:$PATH" iocell console -f "$tag" > "$workdir/running.log" 2>&1
[ "$(jls -j "ioc-$uuid" jid)" = "$jid" ]
[ "$(wc -l < "$workdir/login.trace" | tr -d ' ')" = 2 ]
echo 'PASS: native forced console on a running jail retains the same kernel jail'
iocell stop "$uuid" > "$workdir/stop.log" 2>&1
[ "$(iocell get state "$uuid")" = down ]
echo 'PASS: native forced-console fixture stops cleanly'
iocell set istemplate=yes "$uuid" > "$workdir/template.log" 2>&1
ds="$IOC_TEST_POOL/iocell/templates/$tag"
mp=$(zfs get -H -o value mountpoint "$ds")
cp "$mp/config" "$workdir/template-before"
guid=$(zfs get -H -o value guid "$ds/root")
status=0
PATH="$workdir/bin:$PATH" iocell console -f "$tag" > "$workdir/refused.log" 2>&1 || status=$?
[ "$status" = 1 ]
grep -q 'cannot start a template through console' "$workdir/refused.log"
[ "$(wc -l < "$workdir/login.trace" | tr -d ' ')" = 2 ]
if jls -j "ioc-$tag" jid >/dev/null 2>&1; then exit 1; fi
cmp "$mp/config" "$workdir/template-before"
[ "$(zfs get -H -o value guid "$ds/root")" = "$guid" ]
echo 'PASS: native forced console refuses template startup without changing config or GUID'
