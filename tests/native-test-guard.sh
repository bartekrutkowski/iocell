#!/bin/sh
# A pool name alone must never authorize native/destructive tests.
set -eu
cd "$(dirname "$0")/.."
if [ ! -f tests/native-common.sh ]; then
    echo 'FAIL: native tests have no shared destructive opt-in guard'
    exit 1
fi
. ./tests/native-common.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-native-guard.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
uname () { [ "$*" = -s ] || return 99; echo "$test_os"; }
id () { [ "$*" = -u ] || return 99; echo "$test_uid"; }
zfs () {
    echo "zfs $*" >> "$trace"
    [ "$property_error" = no ] || return 42
    [ "$*" = 'get -H -s local -o value org.freebsd.iocell:test tank' ] || return 99
    echo "$marker"
}
df () {
    [ "$*" = '-P /iocell' ] || return 99
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n'
    printf '%s 100 1 99 1%% /iocell\n' "$mounted_dataset"
}
uclcmd () {
    [ "$*" = 'get -qf /iocell/.default pool' ] || return 99
    echo "$selected_pool"
}
failed=0
for label in opt-in missing-pool platform credentials unmarked query wrong-mount wrong-selection accepted; do
    trace="$workdir/$label.trace"; : > "$trace"
    test_os=FreeBSD; test_uid=0; marker=yes; property_error=no
    mounted_dataset=tank/iocell; selected_pool=tank
    IOC_TEST_DESTRUCTIVE=yes; IOC_TEST_POOL=tank; want=1
    case "$label" in
        opt-in) unset IOC_TEST_DESTRUCTIVE ;;
        missing-pool) unset IOC_TEST_POOL ;;
        platform) test_os=Linux ;;
        credentials) test_uid=1000 ;;
        unmarked) marker=- ;;
        query) property_error=yes ;;
        wrong-mount) mounted_dataset=production/iocell ;;
        wrong-selection) selected_pool=production ;;
        accepted) want=0 ;;
    esac
    status=0
    ( ioc_test_require_pool ) > "$workdir/$label.out" 2> "$workdir/$label.err" || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: native guard $label returned $status, expected $want"
        failed=1; continue
    fi
    if [ "$want" = 1 ] && [ ! -s "$workdir/$label.err" ]; then
        echo "FAIL: native guard $label has no diagnostic"; failed=1; continue
    fi
    case "$label" in
        opt-in|missing-pool|platform|credentials)
            [ ! -s "$trace" ] || { echo "FAIL: $label probed a pool"; failed=1; continue; } ;;
    esac
    echo "PASS: native guard $label"
done
# Execute the receiver program in a subshell, keeping only system boundaries fake.
ssh () {
    printf 'ssh %s\n' "$*" >> "$trace"
    ( set -- "$IOC_TEST_REMOTE_POOL"; . /dev/stdin )
}
for label in opt-in missing-peer missing-pool unsafe-pool platform credentials unmarked query accepted; do
    trace="$workdir/remote-$label.trace"; : > "$trace"
    test_os=FreeBSD; test_uid=0; marker=yes; property_error=no; want=1
    IOC_TEST_REMOTE_DESTRUCTIVE=yes; IOC_TEST_REMOTE=root@disposable
    IOC_TEST_REMOTE_POOL=tank
    case "$label" in
        opt-in) unset IOC_TEST_REMOTE_DESTRUCTIVE ;;
        missing-peer) unset IOC_TEST_REMOTE ;;
        missing-pool) unset IOC_TEST_REMOTE_POOL ;;
        unsafe-pool) IOC_TEST_REMOTE_POOL='tank;exit' ;;
        platform) test_os=Linux ;; credentials) test_uid=1000 ;;
        unmarked) marker=- ;; query) property_error=yes ;; accepted) want=0 ;;
    esac
    status=0
    ( ioc_test_require_remote ) > "$workdir/remote-$label.out" \
        2> "$workdir/remote-$label.err" || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: receiver guard $label returned $status expected $want"; failed=1; continue
    fi
    case "$label" in opt-in|missing-peer|missing-pool|unsafe-pool)
        if [ -s "$trace" ]; then echo "FAIL: receiver $label made SSH contact"; failed=1; continue; fi ;;
    esac
    echo "PASS: receiver guard $label"
done
mkdir "$workdir/deny"
cat > "$workdir/deny/denied" <<'DENIED'
#!/bin/sh
printf '%s %s\n' "$0" "$*" >> "$IOC_GUARD_TRACE"
exit 99
DENIED
chmod +x "$workdir/deny/denied"
for cmd in zfs zpool jail mount umount mktemp mkdir truncate rm cp mv touch chmod chflags; do
    ln -s denied "$workdir/deny/$cmd"
done
for script in tests/*-zfs.sh; do
    trace="$workdir/$(basename "$script").guard"; : > "$trace"; status=0
    (
        unset IOC_TEST_DESTRUCTIVE IOC_TEST_REMOTE_DESTRUCTIVE
        export IOC_GUARD_TRACE="$trace" PATH="$workdir/deny:$PATH"
        sh "$script"
    ) > "$trace.log" 2>&1 || status=$?
    if [ "$status" = 0 ] || [ -s "$trace" ] ||
        ! grep -q 'Native test refused: set IOC_TEST_DESTRUCTIVE=yes' "$trace.log"; then
        echo "FAIL: $script did not refuse before system changes"; failed=1
    else echo "PASS: $script refuses unauthorized execution"; fi
done
exit "$failed"
