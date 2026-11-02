#!/bin/sh
# Real jail-name safety, stream publication and retained failed-send snapshots.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-export-zfs.XXXXXX)
echo "Retained native export logs: $workdir"
id=''
cleanup () {
    [ -z "$id" ] || jail -r "ioc-$id" >> "$workdir/stop.log" 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
id=$(sh ./iocell create -e "tag=export-$(uuidgen)")
ds="$IOC_TEST_POOL/iocell/jails/$id"
# A valid literal '[' mountpoint defeats grep-based detection of a live jail.
zfs set mountpoint="$workdir/owned[ab]" "$ds"
mp=$(zfs get -H -o value mountpoint "$ds")
echo retained > "$mp/root/canary"
cp -p "$mp/config" "$workdir/config.before"
jail -c "name=ioc-$id" "path=$mp/root" persist
jls -j "ioc-$id" > "$workdir/running-jail"
zfs list -H -p -t all -r -o name,guid "$ds" > "$workdir/live.before"
status=0
sh ./iocell export "$id" > "$workdir/live.log" 2>&1 || status=$?
[ "$status" != 0 ]
zfs list -H -p -t all -r -o name,guid "$ds" > "$workdir/live.after"
cmp "$workdir/live.before" "$workdir/live.after"
cmp "$mp/config" "$workdir/config.before"
jail -r "ioc-$id"
zfs inherit mountpoint "$ds"
mp=$(zfs get -H -o value mountpoint "$ds")
echo 'PASS: native export refuses a live jail at a literal metacharacter path'
sh ./iocell export "$id" > "$workdir/export.log" 2>&1
image=$(find "$IOC_TEST_ROOT/images" -type f -name "$id-emptyjail-*")
[ -n "$image" ] && [ -s "$image" ]
[ "$(stat -f %Lp "$image")" = 600 ]
[ "$(cat "$mp/root/canary")" = retained ]
cmp "$mp/config" "$workdir/config.before"
echo 'PASS: native stopped export publishes a private complete raw image'

id=$(sh ./iocell create -e "tag=export-failed-$(uuidgen)")
ds="$IOC_TEST_POOL/iocell/jails/$id"
mp=$(zfs get -H -o value mountpoint "$ds")
echo retained > "$mp/root/canary"
mkdir "$workdir/bin"
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
if [ "$1" = send ]; then printf partial-stream; exit 43; fi
exec /sbin/zfs "$@"
WRAPPER
chmod +x "$workdir/bin/zfs"
status=0
env PATH="$workdir/bin:$PATH" sh ./iocell export "$id" \
    > "$workdir/send-failure.log" 2>&1 || status=$?
[ "$status" = 43 ]
partial=$(find "$IOC_TEST_ROOT/images" -type f -name "$id-emptyjail-*.partial")
[ -n "$partial" ] && [ "$(cat "$partial")" = partial-stream ]
[ ! -e "${partial%.partial}" ]
zfs list -H -t snapshot -o name -r "$ds" > "$workdir/snapshots-retained"
grep -F "$ds@ioc-export-" "$workdir/snapshots-retained"
[ "$(cat "$mp/root/canary")" = retained ]
echo 'PASS: native failed send preserves partial image, source data and snapshot'
