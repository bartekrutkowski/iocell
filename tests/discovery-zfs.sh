#!/bin/sh
# Real legacy migration and bulk-stop continuation; only new fixtures are changed.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set a fetched release for the real basejail fixture}"
[ "$(jls -h jid | wc -l | tr -d ' ')" = 1 ] || {
    ioc_test_error 'stop all jails before the discovery/bulk-stop test'; exit 1;
}
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
workdir=$(mktemp -d /var/tmp/iocell-discovery-zfs.XXXXXX)
echo "Retained discovery logs: $workdir"
find_all () (
    # Match the CLI's optional-property semantics, rather than shell nounset.
    set +u
    . ./lib/ioc-globals
    . ./lib/ioc-common
    . ./lib/ioc-info
    . ./lib/ioc-configure
    . ./lib/ioc-zfs
    pool="$IOC_TEST_POOL"; iocroot="$IOC_TEST_ROOT"
    __find_jail ALL
)
id=$(iocell create -e "tag=legacy-$(uuidgen)")
ds="$IOC_TEST_POOL/iocell/jails/$id"
mp=$(zfs get -H -o value mountpoint "$ds")
echo legacy-content > "$mp/root/discovery-marker"
zfs set compression=off quota=64M "org.freebsd.iocell:host_hostuuid=$id" \
    org.freebsd.iocell:type=basejail "org.freebsd.iocell:tag=legacy-$id" \
    "org.freebsd.iocell:notes=alpha=beta's data" "$ds"
guid=$(zfs get -H -o value guid "$ds/root")
mv "$mp/config" "$workdir/config-original"
find_all > "$workdir/legacy.out" 2> "$workdir/legacy.err"
[ "$(uclcmd get -qf "$mp/config" host_hostuuid)" = "$id" ]
[ "$(uclcmd get -qf "$mp/config" notes)" = "alpha=beta's data" ]
[ "$(uclcmd get -qf "$mp/config" test)" = null ]
[ "$(zfs get -H -o value compression "$ds")" = off ]
[ "$(zfs get -Hp -o value quota "$ds")" = 67108864 ]
[ "$(zfs get -H -o value guid "$ds/root")" = "$guid" ]
[ "$(cat "$mp/root/discovery-marker")" = legacy-content ]
echo 'PASS: native legacy migration preserves values, native properties and data'

# Fail an actual UCL write; migration must leave no partially published config.
mkdir "$workdir/bin"
cat > "$workdir/bin/uclcmd" <<'WRAPPER'
#!/bin/sh
for last; do :; done
if [ "$1" = set ] && [ "$last" = "alpha=beta's data" ]; then
    echo 'injected legacy UCL write failure' >&2
    exit 42
fi
exec /usr/local/bin/uclcmd "$@"
WRAPPER
chmod +x "$workdir/bin/uclcmd"
mv "$mp/config" "$workdir/migrated-before-fault"
PATH="$workdir/bin:$PATH" find_all > "$workdir/fault.out" 2> "$workdir/fault.err"
grep -q 'injected legacy UCL write failure' "$workdir/fault.err"
grep -Fx "$ds" "$workdir/fault.out"
[ ! -e "$mp/config" ]
find_all > "$workdir/retry.out" 2> "$workdir/retry.err"
cmp "$mp/config" "$workdir/migrated-before-fault"
echo 'PASS: native failed migration publishes no config and a retry succeeds'

suffix=$(uuidgen | tr -d '-' | cut -c1-12)
bad="00000000-0000-0000-0000-$suffix"
bad_ds="$IOC_TEST_POOL/iocell/jails/$bad"
zfs create -p "$bad_ds/root"
bad_root=$(zfs get -H -o value mountpoint "$bad_ds/root")
unconfigured="$IOC_TEST_POOL/iocell/templates/unconfigured-$suffix"
zfs create "$unconfigured"
find_all > "$workdir/incomplete.out" 2> "$workdir/incomplete.err"
grep -Fx "$bad_ds" "$workdir/incomplete.out"
grep -Fx "$unconfigured" "$workdir/incomplete.out"
grep -q 'missing configuration:' "$workdir/incomplete.err"
[ ! -e "${bad_root%/root}/config" ]
echo 'PASS: native incomplete identities remain visible without fabricated config'

good=''
cleanup () {
    [ -z "$good" ] || iocell stop "$good" >/dev/null 2>&1 || :
    jail -r "ioc-$bad" >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
jail -c "name=ioc-$bad" "path=$bad_root" persist ip4=disable ip6=disable
tag="bulk-good-$suffix"
iocell create "release=$IOC_TEST_RELEASE" "tag=$tag" vnet=off \
    ip4_addr=none ip6_addr=none > "$workdir/create-good.log" 2>&1
good=$(iocell get host_hostuuid "$tag")
iocell start "$good" > "$workdir/start-good.log" 2>&1
status=0
iocell stop ALL > "$workdir/stop-all.log" 2>&1 || status=$?
[ "$status" = 1 ]
grep -q "cannot stop $bad: missing or invalid configuration" "$workdir/stop-all.log"
jls -j "ioc-$bad" jid > "$workdir/bad-still-running.log"
if jls -j "ioc-$good" jid > "$workdir/good-stopped.log" 2>&1; then
    echo 'FAIL: stop ALL skipped the later valid jail' >&2; exit 1
fi
echo 'PASS: native stop ALL reports the unconfigured jail and stops the later basejail'
zpool status -x
