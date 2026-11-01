#!/bin/sh
# Public multi-target start: real later jail creation and failed-jail preservation.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set a fetched release}"
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
workdir=$(mktemp -d /var/tmp/iocell-start-multi.XXXXXX)
echo "Retained multi-start logs: $workdir"
first=$(iocell create -e "tag=start-first-$(uuidgen)" vnet=off ip4_addr=none ip6_addr=none)
second=$(iocell create -e "tag=start-second-$(uuidgen)" vnet=off ip4_addr=none ip6_addr=none)
tag="start-good-$(uuidgen)"
iocell create "release=$IOC_TEST_RELEASE" "tag=$tag" vnet=off ip4_addr=none \
    ip6_addr=none > "$workdir/create-good.log" 2>&1
good=$(iocell get host_hostuuid "$tag")
cleanup () {
    for uuid in "$first" "$second" "$good"; do
        iocell stop "$uuid" >/dev/null 2>&1 || :
    done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
for uuid in "$first" "$second"; do iocell set type=thickjail "$uuid"; done
first_ds="$IOC_TEST_POOL/iocell/jails/$first"
second_ds="$IOC_TEST_POOL/iocell/jails/$second"
first_mp=$(zfs get -H -o value mountpoint "$first_ds")
second_mp=$(zfs get -H -o value mountpoint "$second_ds")
echo first-preserved > "$first_mp/root/canary"
echo second-preserved > "$second_mp/root/canary"
first_guid=$(zfs get -H -o value guid "$first_ds/root")
second_guid=$(zfs get -H -o value guid "$second_ds/root")
mkdir "$workdir/bin"
real_jail=$(command -v jail)
cat > "$workdir/bin/jail" <<WRAPPER
#!/bin/sh
case " \$* " in
    *" name=ioc-$first "*) echo 'injected first jail failure' >&2; exit 42 ;;
    *" name=ioc-$second "*) echo 'injected second jail failure' >&2; exit 43 ;;
esac
exec "$real_jail" "\$@"
WRAPPER
chmod +x "$workdir/bin/jail"
for mode in interfaces returned multiple late; do
    iocell stop "$good" > "$workdir/$mode-stop.log" 2>&1 || :
    if [ "$mode" = interfaces ]; then iocell set interfaces=malformed "$first"
    else iocell set interfaces=vnet0:bridge0 "$first"; fi
    cp "$first_mp/config" "$workdir/first-before"
    cp "$second_mp/config" "$workdir/second-before"
    want=42; status=0
    case "$mode" in
        interfaces) set -- "$first" "$good"; want=1 ;;
        returned) set -- "$first" "$good" ;;
        multiple) set -- "$first" "$second" "$good" ;;
        late) set -- "$good" "$first" ;;
    esac
    PATH="$workdir/bin:$PATH" iocell start "$@" > "$workdir/$mode.log" 2>&1 || status=$?
    [ "$status" = "$want" ]
    if ! jls -j "ioc-$good" jid > "$workdir/$mode-jid"; then
        echo "FAIL: $mode failed to start the other valid jail" >&2; exit 1
    fi
    for uuid in "$first" "$second"; do
        if jls -j "ioc-$uuid" jid >/dev/null 2>&1; then exit 1; fi
    done
    case "$mode" in returned|multiple|late) grep -q 'injected first jail failure' "$workdir/$mode.log" ;; esac
    [ "$mode" != multiple ] || grep -q 'injected second jail failure' "$workdir/$mode.log"
    cmp "$first_mp/config" "$workdir/first-before"
    cmp "$second_mp/config" "$workdir/second-before"
    [ "$(cat "$first_mp/root/canary")" = first-preserved ]
    [ "$(cat "$second_mp/root/canary")" = second-preserved ]
    [ "$(zfs get -H -o value guid "$first_ds/root")" = "$first_guid" ]
    [ "$(zfs get -H -o value guid "$second_ds/root")" = "$second_guid" ]
    echo "PASS: native start $mode preserves first failure, starts valid target and retains failed-jail state"
done
