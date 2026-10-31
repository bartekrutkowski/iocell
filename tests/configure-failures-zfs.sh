#!/bin/sh
# Actual CLI create/clone must not publish success after a real UCL write error.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-configure-failures-zfs.XXXXXX)
echo "Retained configuration failure logs: $workdir"
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
source=$(iocell create -e count=1 "tag=config-source-$(uuidgen)")
source_ds="$IOC_TEST_POOL/iocell/jails/$source"
source_mp=$(zfs get -H -o value mountpoint "$source_ds")
mkdir -p "$source_mp/root/etc"
echo 'hostname="fixture"' > "$source_mp/root/etc/rc.conf"
echo preserved > "$source_mp/root/canary"
zfs snapshot -r "$source_ds@config-saved"
cp "$source_mp/config" "$workdir/source-before"
guid=$(zfs get -H -o value guid "$source_ds/root")
before=$(sha256 -q "$IOC_TEST_ROOT/.default")
mkdir "$workdir/bin"
cat > "$workdir/bin/uclcmd" <<'WRAPPER'
#!/bin/sh
for last; do :; done
if [ "$1" = set ] && [ "$last" = "$IOC_CONFIG_FAULT" ]; then
    echo 'injected configuration generation error' >&2; exit 42
fi
exec /usr/local/bin/uclcmd "$@"
WRAPPER
chmod +x "$workdir/bin/uclcmd"
failed=0
for mode in create clone; do
    token="config-fault-$(uuidgen)"; tag="failed-config-$(uuidgen)"
    zfs list -rHd1 -o name "$IOC_TEST_POOL/iocell/jails" | sort > "$workdir/$mode.before"
    status=0
    if [ "$mode" = create ]; then
        env PATH="$workdir/bin:$PATH" IOC_CONFIG_FAULT="$token" sh ./iocell \
            create -e count=1 "tag=$tag" "notes=$token" \
            > "$workdir/$mode.out" 2> "$workdir/$mode.err" || status=$?
    else
        env PATH="$workdir/bin:$PATH" IOC_CONFIG_FAULT="$token" sh ./iocell \
            clone "$source@config-saved" "tag=$tag" "notes=$token" \
            > "$workdir/$mode.out" 2> "$workdir/$mode.err" || status=$?
    fi
    zfs list -rHd1 -o name "$IOC_TEST_POOL/iocell/jails" | sort > "$workdir/$mode.after"
    comm -13 "$workdir/$mode.before" "$workdir/$mode.after" > "$workdir/$mode.new"
    [ "$(wc -l < "$workdir/$mode.new" | tr -d ' ')" = 1 ]
    target=$(cat "$workdir/$mode.new")
    zfs get -H -o value guid "$target/root" > "$workdir/$mode.target-guid"
    if [ "$status" != 42 ] || [ -L "$IOC_TEST_ROOT/tags/$tag" ] || \
        grep -Eq 'Successfully created|^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' "$workdir/$mode.out" || \
        ! grep -q 'injected configuration generation error' "$workdir/$mode.err"; then
        echo "FAIL: native $mode ignored a configuration write failure"; failed=1
    else echo "PASS: native $mode stops publication on a configuration write failure"; fi
    if [ "$mode" = clone ]; then
        target_mp=$(zfs get -H -o value mountpoint "$target")
        [ "$(cat "$target_mp/root/canary")" = preserved ]
    fi
done
cmp "$source_mp/config" "$workdir/source-before"
[ "$(cat "$source_mp/root/canary")" = preserved ]
[ "$(zfs get -H -o value guid "$source_ds/root")" = "$guid" ]
echo 'PASS: failed configuration publication preserves source config, data and GUID'
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: failed configuration publication preserves activation'
zpool status -x
exit "$failed"
