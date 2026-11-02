#!/bin/sh
# Real CLI/UCL literal values and first-error ordering on new fixtures only.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
workdir=$(mktemp -d /var/tmp/iocell-set-values.XXXXXX)
echo "Retained set-value logs: $workdir"
id=$(uuidgen)
note="worker's  literal \$(touch $workdir/not-executed)=value"
first=$(iocell create -e "tag=set-values-first-$id" "notes=$note")
[ "$(iocell get notes "$first")" = "$note" ]
[ ! -e "$workdir/not-executed" ]
echo 'PASS: native creation preserves a literal quoted property value'
second=$(iocell create -e "tag=set-values-second-$id")
mp=$(zfs get -H -o value mountpoint "$IOC_TEST_POOL/iocell/jails/$first")
other=$(zfs get -H -o value mountpoint "$IOC_TEST_POOL/iocell/jails/$second")
command='env REVIEW=alpha=beta /bin/sh /etc/rc'
iocell set "exec_start=$command" "notes=$note" "$first"
[ "$(iocell get exec_start "$first")" = "$command" ]
[ "$(iocell get notes "$first")" = "$note" ]
[ ! -e "$workdir/not-executed" ]
echo 'PASS: native set preserves equals, apostrophes, whitespace and literal shell text'
owner='first
second=value'
iocell set "owner=$owner" "$first"
[ "$(uclcmd get -qf "$mp/config" owner)" = "$owner" ]
echo 'PASS: native set preserves a multiline value'

for property in notes owner; do
    iocell set "$property=null" "$first"
    [ "$(uclcmd get -f "$mp/config" "$property")" = '"null"' ]
    [ "$(iocell get "$property" "$first")" = null ]
done
# Restore the multiline value used by the subsequent failure-ordering case.
iocell set "owner=$owner" "$first"
zfs set compression=lz4 "$IOC_TEST_POOL/iocell/jails/$first"
[ "$(iocell get compression "$first")" = lz4 ]
echo 'PASS: native get distinguishes literal null from absent native properties'

mkdir "$workdir/bin"
cat > "$workdir/bin/uclcmd" <<'WRAPPER'
#!/bin/sh
for last; do :; done
if [ "$1" = get ] && [ "$last" = notes ]; then
    case "${IOC_PROP_FAULT:-}:$2" in parser:-qf) exit 43 ;; raw:-f) exit 44 ;; esac
fi
if [ "$1" = set ] && [ "$last" = fail-after ]; then
    echo 'injected set-value write failure' >&2
    exit 42
fi
exec /usr/local/bin/uclcmd "$@"
WRAPPER
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
if [ "${IOC_PROP_FAULT:-}" = mount ] &&
    [ "$*" = "get -H -o value mountpoint $IOC_PROP_DATASET" ]; then exit 42; fi
exec /sbin/zfs "$@"
WRAPPER
chmod +x "$workdir/bin/uclcmd" "$workdir/bin/zfs"
cp "$other/config" "$workdir/second-before"
status=0
PATH="$workdir/bin:$PATH" iocell set notes=first-applied owner=fail-after \
    boot=on "$first" "$second" > "$workdir/failure.log" 2>&1 || status=$?
[ "$status" = 42 ]
grep -q 'injected set-value write failure' "$workdir/failure.log"
[ "$(iocell get notes "$first")" = first-applied ]
[ "$(iocell get owner "$first")" = "$owner" ]
[ "$(iocell get boot "$first")" = off ]
cmp "$other/config" "$workdir/second-before"
echo 'PASS: native set stops later properties and jails at the first write failure'
iocell set notes=null "$first"
for fault in mount parser raw; do
    status=0; case "$fault" in mount) want=42 ;; parser) want=43 ;; raw) want=44 ;; esac
    env PATH="$workdir/bin:$PATH" IOC_PROP_FAULT="$fault" \
        IOC_PROP_DATASET="$IOC_TEST_POOL/iocell/jails/$first" \
        sh ./iocell get notes "$first" > "$workdir/get-$fault.log" 2>&1 || status=$?
    [ "$status" = "$want" ]
    echo "PASS: native get preserves $fault query failure"
done
zpool status -x
