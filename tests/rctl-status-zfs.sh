#!/bin/sh
# Actual rule application/removal and startup refusal after a kernel error.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set IOC_TEST_RELEASE to a fetched FreeBSD release}"
workdir=$(mktemp -d /var/tmp/iocell-rctl-status.XXXXXX)
echo "Retained resource-limit logs: $workdir"
id=''
cleanup () {
    [ -z "$id" ] || sh ./iocell stop "$id" >> "$workdir/stop.log" 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
rctl > "$workdir/rules-before"
tag="rctl-$(uuidgen)"
sh ./iocell create "release=$IOC_TEST_RELEASE" "tag=$tag" > "$workdir/create.log" 2>&1
id=$(sh ./iocell get host_hostuuid "$tag")
start_status=0
output=$(sh ./iocell start "$id" 2>&1) || start_status=$?
printf '%s\n' "$output" > "$workdir/start.log"
[ "$start_status" = 0 ]
sh ./iocell set rlimits=on maxproc=64:deny "$id"
sh ./iocell cap "$id" > "$workdir/cap.log" 2>&1
rctl -h > "$workdir/rules-capped"
grep -F "jail:ioc-$id:maxproc:deny=64" "$workdir/rules-capped"
echo 'PASS: native cap installs the configured kernel rule'
sh ./iocell uncap "$id" > "$workdir/uncap.log" 2>&1
rctl > "$workdir/rules-uncapped"
if grep -F "jail:ioc-$id:" "$workdir/rules-uncapped"; then exit 1; fi
sh ./iocell limits > "$workdir/limits.log" 2>&1
echo 'PASS: native uncap removes rules and successful listings return zero'
sh ./iocell stop "$id" >> "$workdir/stop.log" 2>&1
mkdir "$workdir/bin"
cat > "$workdir/bin/rctl" <<'WRAPPER'
#!/bin/sh
if [ "$1" = -a ]; then echo 'injected kernel limit failure' >&2; exit 42; fi
exec /usr/bin/rctl "$@"
WRAPPER
chmod +x "$workdir/bin/rctl"
status=0
env PATH="$workdir/bin:$PATH" sh ./iocell start "$id" \
    > "$workdir/start-failure.log" 2>&1 || status=$?
[ "$status" = 42 ]
if jls -j "ioc-$id" >/dev/null 2>&1; then exit 1; fi
mount > "$workdir/mounts-after-failure"
if grep -F "/jails/$id/root/" "$workdir/mounts-after-failure"; then exit 1; fi
sh ./iocell inuse > "$workdir/inuse-stopped.log" 2>&1
echo 'PASS: native startup preserves limit failure and removes its unstarted jail'
