#!/bin/sh
# Native entrypoint checks; invalid commands must never reach stateful tools.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname -s)" = FreeBSD ] && [ "$(id -u)" = 0 ] || exit 1
: "${IOC_TEST_POOL:?Set the activated disposable test pool}"
: "${IOC_TEST_RELEASE:?Set a fetched test release}"
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
[ "$(iocell get pool default)" = "$IOC_TEST_POOL" ]
workdir=$(mktemp -d /var/tmp/iocell-cli-args.XXXXXX)
echo "Retained CLI logs: $workdir"
running=0
cleanup () {
    status=$?
    trap - EXIT
    if [ "$running" = 1 ]; then
        iocell stop "$target" > "$workdir/cleanup.log" 2>&1 || status=1
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
if [ "${IOC_CLI_RED_ONLY:-0}" = 1 ]; then
    target=$(iocell create -e "tag=cli-red-$$")
else
    iocell create "release=$IOC_TEST_RELEASE" "tag=cli-args-$$" \
        vnet=off ip4_addr=none ip6_addr=none boot=off notes=preserved \
        > "$workdir/create.log" 2>&1
    target=$(iocell get host_hostuuid "cli-args-$$")
fi
printf '%s\n' "$target" > "$workdir/uuid"
mp="/iocell/jails/$target"; ds="$IOC_TEST_POOL/iocell/jails/$target"
echo preserved > "$mp/root/cli-canary"
cp "$mp/config" "$workdir/config-before"
cp /iocell/.default "$workdir/default-before"
guid=$(zfs get -H -o value guid "$ds/root")
zfs list -rHt filesystem,snapshot -o name "$IOC_TEST_POOL/iocell" \
    > "$workdir/datasets-before"
failed=0
. ./tests/cli-args-cases.sh
reject () {
    label=$1; shift
    trace="$workdir/$label.trace"; : > "$trace"; status=0
    if [ "${IOC_CLI_RED_ONLY:-0}" = 1 ]; then
        iocell "$@" > "$workdir/$label.log" 2>&1 || status=$?
    else
        PATH="$workdir/bin:$PATH" IOC_CLI_GUARD_TRACE="$trace" \
            iocell "$@" > "$workdir/$label.log" 2>&1 || status=$?
    fi
    if [ "$status" = 0 ] || [ -s "$trace" ] || \
        [ ! -s "$workdir/$label.log" ]; then
        echo "FAIL: native $label: status=$status; see $workdir/$label.log"
        failed=1
    else
        echo "PASS: native CLI rejects $label before stateful tools"
    fi
}
if [ "${IOC_CLI_RED_ONLY:-0}" = 1 ]; then
    # Safe original reproducers only: never run destructive tail cases unguarded.
    reject unknown definitely-not-a-command
    for cmd in destroy start stop reboot restart; do reject "missing-$cmd" "$cmd"; done
    reject force-missing destroy -f
    reject soft-missing restart -s
    reject get-option get -z "$target"
else
    mkdir "$workdir/bin"
    cat > "$workdir/bin/deny" <<'WRAPPER'
#!/bin/sh
printf '%s\n' "${0##*/}" "$@" >> "$IOC_CLI_GUARD_TRACE"
echo 'fixture: stateful tool reached before argument rejection' >&2
exit 42
WRAPPER
    chmod +x "$workdir/bin/deny"
    # Block file mutations too: legacy cleanup can run rm after ZFS fails.
    for tool in zfs uclcmd jls jail jexec rctl mount umount ssh \
        rm rmdir mkdir mv cp touch chmod chown sed fetch git pkg; do
        ln -s deny "$workdir/bin/$tool"
    done
    cli_invalid_cases
    reject verbose-missing -v
    reject version-extra version ignored
    reject long-version-extra --version ignored
    reject verbose-version-extra -v version ignored
fi
cmp "$mp/config" "$workdir/config-before"
cmp /iocell/.default "$workdir/default-before"
[ "$(cat "$mp/root/cli-canary")" = preserved ]
[ "$(zfs get -H -o value guid "$ds/root")" = "$guid" ]
zfs list -rHt filesystem,snapshot -o name "$IOC_TEST_POOL/iocell" \
    > "$workdir/datasets-after"
cmp "$workdir/datasets-before" "$workdir/datasets-after"
[ "$(iocell get pool default)" = "$IOC_TEST_POOL" ]
echo 'PASS: rejected commands preserve config, defaults, canary, GUID and namespace'
[ "$failed" = 0 ] || exit 1
[ "${IOC_CLI_RED_ONLY:-0}" != 1 ] || exit 0

for spelling in help --help -h version --version; do
    PAGER=cat iocell "$spelling" > "$workdir/valid-$spelling.log" 2>&1
    [ -s "$workdir/valid-$spelling.log" ]
done
PAGER=cat iocell > "$workdir/valid-usage.log" 2>&1
PAGER=cat iocell -v help > "$workdir/valid-verbose-help.log" 2>&1
iocell -v version > "$workdir/valid-verbose-version.log" 2>&1
grep -q '^iocell [[:digit:]]' "$workdir/valid-verbose-version.log"
echo 'PASS: no-argument usage, help/version aliases and verbose forms succeed'
[ "$(iocell get notes "$target")" = preserved ]
iocell list -s > "$workdir/valid-list.log"
iocell get -r notes > "$workdir/valid-recursive-get.log"
echo 'PASS: ordinary and recursive property reads and optional list sorting succeed'

iocell snapshot -f -r "$target@cli-valid" > "$workdir/snapshot.log" 2>&1
zfs list "$ds@cli-valid" "$ds/root@cli-valid" > "$workdir/snapshot-datasets.log"
echo 'PASS: forced recursive snapshot still covers parent and root'
running=1
iocell start -f "$target" > "$workdir/start.log" 2>&1
status=0
iocell exec -u root "$target" /bin/sh -c 'printf "%s\n" "two words"; exit 17' \
    > "$workdir/exec.log" 2>&1 || status=$?
[ "$status" = 17 ]
grep -Fx 'two words' "$workdir/exec.log"
iocell restart -s "$target" > "$workdir/restart.log" 2>&1
iocell reboot "$target" > "$workdir/reboot.log" 2>&1
iocell stop "$target" > "$workdir/stop.log" 2>&1
running=0
[ "$(iocell get state "$target")" = down ]
[ "$(cat "$mp/root/cli-canary")" = preserved ]
echo 'PASS: start, soft/hard restart, exec quoting/status and stop remain functional'

# Destroy only this newly identified second fixture; retain the primary fixture.
victim=$(iocell create -e "tag=cli-destroy-$$")
victim_ds="$IOC_TEST_POOL/iocell/jails/$victim"
zfs list "$victim_ds" > "$workdir/victim-before.log"
iocell destroy -f "$victim" > "$workdir/destroy.log" 2>&1
if zfs list "$victim_ds" > "$workdir/victim-after.log" 2>&1; then
    echo 'FAIL: valid destroy left its own target' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$ds/root")" = "$guid" ]
echo 'PASS: valid forced destruction removes only the new disposable target'
zpool status -x
