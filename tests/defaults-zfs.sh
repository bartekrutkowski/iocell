#!/bin/sh
# Opt-in native defaults checks in a new, retained file-backed pool.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
original="$IOC_TEST_POOL"
[ "$(jls -h jid | wc -l | tr -d ' ')" = 1 ] || exit 1
workdir=$(mktemp -d /var/tmp/iocell-defaults-zfs.XXXXXX)
scratch=$(ioc_test_pool_name iocdefaults); activated=0
cleanup () {
    status=$?
    trap - EXIT
    if [ "$activated" = 1 ]; then
        iocell activate "$original" > "$workdir/restore.log" 2>&1 || status=1
    fi
    echo "Retained defaults logs/vdev: $workdir"
    echo "Retained scratch pool: $scratch"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
truncate -s 512M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$scratch" "$workdir/pool.vdev"
# Mark restoration necessary before activation can change mountpoints.
activated=1
iocell activate "$scratch" > "$workdir/activate.log" 2>&1
[ "$(iocell get pool default)" = "$scratch" ]
new_jail () {
    new_uuid=$(iocell create -e "$@")
    printf '%s\n' "$new_uuid" | grep -Eq \
        '^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$'
    new_ds="$scratch/iocell/jails/$new_uuid"
}
new_jail tag=defaults-existing notes=existing
existing=$new_uuid; existing_ds=$new_ds
cp "/iocell/jails/$existing/config" "$workdir/existing-config"
echo preserved > "/iocell/jails/$existing/root/marker"
existing_guid=$(zfs get -H -o value guid "$existing_ds/root")
default_mode=$(stat -f '%Lp:%u:%g' /iocell/.default)
# The original issue #24 reproducer; independent invocations prove persistence.
iocell set vnet=off default > "$workdir/set-vnet.log" 2>&1
[ "$(iocell get vnet default)" = off ]
iocell set 'notes=alpha=beta gamma' priority=42 default
[ "$(iocell get notes default)" = 'alpha=beta gamma' ]
[ "$(stat -f '%Lp:%u:%g' /iocell/.default)" = "$default_mode" ]
iocell defaults > "$workdir/defaults.log"
grep -Fx 'vnet=off' "$workdir/defaults.log"
grep -Fx 'notes=alpha=beta gamma' "$workdir/defaults.log"
echo 'PASS: native default setters persist across commands and defaults display'

new_jail tag=defaults-inherited
inherited=$new_uuid
[ "$(iocell get vnet "$inherited")" = off ]
[ "$(iocell get notes "$inherited")" = 'alpha=beta gamma' ]
[ "$(iocell get priority "$inherited")" = 42 ]
[ "$(iocell get host_hostuuid "$inherited")" = "$inherited" ]
[ "$(iocell get host_hostname "$inherited")" = "$inherited" ]
echo 'PASS: new jail inherits saved defaults and retains fresh identity'
new_jail tag=defaults-override vnet=on notes=explicit priority=7
override=$new_uuid
[ "$override" != "$inherited" ]
[ "$(iocell get vnet "$override")" = on ]
[ "$(iocell get notes "$override")" = explicit ]
[ "$(iocell get priority "$override")" = 7 ]
[ "$(iocell get host_hostuuid "$override")" = "$override" ]
[ "$(iocell get notes default)" = 'alpha=beta gamma' ]
echo 'PASS: explicit creation properties override defaults without rewriting them'

# Writable native defaults belong in UCL, not on the existing jail hierarchy.
root_compression=$(zfs get -H -o value compression "$scratch/iocell")
iocell set compression=off default
[ "$(iocell get compression default)" = off ]
[ "$(zfs get -H -o value compression "$scratch/iocell")" = "$root_compression" ]
new_jail tag=defaults-compression
[ "$(zfs get -H -o value compression "$new_ds")" = off ]
new_jail tag=defaults-compression-override compression=lz4
[ "$(zfs get -H -o value compression "$new_ds")" = lz4 ]
echo 'PASS: native compression default and override affect only new datasets'

iocell set notes=none priority=0 default
new_jail tag=defaults-none
[ "$(iocell get notes "$new_uuid")" = none ]
[ "$(iocell get priority "$new_uuid")" = 0 ]
iocell set notes=null default
new_jail tag=defaults-literal-null
# The existing per-jail getter conflates a string "null" with a missing key.
[ "$(uclcmd get -f "/iocell/jails/$new_uuid/config" notes)" = '"null"' ]
echo 'PASS: literal none, zero and null values are inherited, not treated as missing'

iocell set count=2 default
iocell create -e tag=defaults-count > "$workdir/count.log"
[ "$(wc -l < "$workdir/count.log" | tr -d ' ')" = 2 ]
[ "$(iocell get tag defaults-count_1)" = defaults-count_1 ]
[ "$(iocell get tag defaults-count_2)" = defaults-count_2 ]
iocell set count=1 default
echo 'PASS: saved creation controls are loaded before count processing'

cp /iocell/.default "$workdir/default-before-invalid"
for setting in unknown_property=value notes= vnet=invalid pool=wrong \
    host_hostuuid=wrong origin=wrong; do
    if iocell set "$setting" default > "$workdir/invalid-${setting%%=*}.log" 2>&1; then
        echo "FAIL: invalid default accepted: $setting" >&2; exit 1
    fi
    cmp /iocell/.default "$workdir/default-before-invalid"
done
if iocell set default > "$workdir/missing-property.log" 2>&1; then
    echo 'FAIL: missing default property accepted' >&2; exit 1
fi
cmp /iocell/.default "$workdir/default-before-invalid"
echo 'PASS: unknown, empty, missing, invalid boolean, managed and read-only defaults fail safely'

mkdir "$workdir/bin"
cat > "$workdir/bin/uclcmd" <<'WRAPPER'
#!/bin/sh
if [ "$1" = set ]; then echo 'fixture write error' >&2; exit 42; fi
exec /usr/local/bin/uclcmd "$@"
WRAPPER
chmod +x "$workdir/bin/uclcmd"
status=0
PATH="$workdir/bin:$PATH" iocell set notes=failed default \
    > "$workdir/write-failure.log" 2>&1 || status=$?
[ "$status" = 42 ]
cmp /iocell/.default "$workdir/default-before-invalid"
echo 'PASS: UCL write failure propagates without replacing the defaults'

# Keep pool lookup valid but force the real UCL writer to parse malformed input.
mkdir "$workdir/broken"
printf '{ broken = "unterminated\n' > "$workdir/broken/.default"
cp "$workdir/broken/.default" "$workdir/broken-before"
if ( . ./lib/ioc-common; . ./lib/ioc-globals
    iocroot="$workdir/broken"; __set_jail_prop notes=failed default
) > "$workdir/parser-failure.log" 2>&1; then
    echo 'FAIL: malformed defaults accepted' >&2; exit 1
fi
cmp "$workdir/broken/.default" "$workdir/broken-before"
echo 'PASS: actual UCL parse failure preserves malformed defaults for inspection'

cmp "/iocell/jails/$existing/config" "$workdir/existing-config"
[ "$(cat "/iocell/jails/$existing/root/marker")" = preserved ]
[ "$(zfs get -H -o value guid "$existing_ds/root")" = "$existing_guid" ]
[ "$(iocell get pool default)" = "$scratch" ]
echo 'PASS: existing jail configuration, data, GUID and active pool are unchanged'
zpool status -x
