#!/bin/sh
# Opt-in native SSH replication checks, including real optional mbuffer.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
ioc_test_require_remote
: "${IOC_TEST_REMOTE:?Set root@private-disposable-FreeBSD-receiver}"
peer="$IOC_TEST_REMOTE"
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
remote () { /usr/bin/ssh "$peer" "$@"; }
original="$IOC_TEST_POOL"
[ "$(remote uname -s)" = FreeBSD ]
command -v mbuffer >/dev/null
remote /usr/bin/which -s mbuffer
workdir=$(mktemp -d /var/tmp/iocell-remote-safety.XXXXXX)
src=$(ioc_test_pool_name iocrsrc); dst=$(ioc_test_pool_name iocrrx); activated=0
cleanup () {
    status=$?
    trap - EXIT
    if [ "$activated" = 1 ]; then
        iocell activate "$original" > "$workdir/restore.log" 2>&1 || status=1
    fi
    echo "Retained remote safety logs/vdevs: $workdir"
    echo "Retained pools: local $src $dst; receiver $dst $src"
    echo "Receiver vdevs: /var/tmp/$dst.vdev /var/tmp/$src.vdev"
    echo "Receiver wrapper: /var/tmp/$dst-fault/mbuffer"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
for p in "$src" "$dst"; do
    truncate -s 512M "$workdir/$p.vdev"
    zpool create -O mountpoint=none "$p" "$workdir/$p.vdev"
done
remote "truncate -s 512M /var/tmp/$dst.vdev; zpool create -O mountpoint=none $dst /var/tmp/$dst.vdev"
iocell activate "$src" > "$workdir/activate.log" 2>&1
activated=1
u=$(iocell create -e tag=remote-safety)
root="$src/iocell/jails/$u/root"
mp=$(zfs get -H -o value mountpoint "$root")
guid=$(zfs get -H -o value guid "$root")
mkdir "$workdir/plain" "$workdir/fault" "$workdir/csh"
# Force the no-buffer branch even though mbuffer is installed for later cases.
cat > "$workdir/plain/which" <<'WHICH'
#!/bin/sh
[ "$*" != '-s mbuffer' ] || exit 1
exec /usr/bin/which "$@"
WHICH
chmod +x "$workdir/plain/which"
# Route only the production receiver command through a real csh parser. The
# login account need not be modified, and all probes still use ordinary SSH.
cat > "$workdir/csh/ssh" <<'CSH'
#!/bin/sh
case "$*" in
    *iocell-receive.XXXXXX*)
        peer=$1; shift
        quoted=$(printf '%s' "$*" | sed "s/'/'\\\\''/g")
        exec /usr/bin/ssh "$peer" "/bin/csh -c '$quoted'" ;;
    *) exec /usr/bin/ssh "$@" ;;
esac
CSH
chmod +x "$workdir/csh/ssh"
# A real buffer completing a real stream, then reporting a failure.
cat > "$workdir/fault/mbuffer" <<'BUFFER'
#!/bin/sh
/usr/local/bin/mbuffer "$@" || exit $?
echo 'injected real buffer failure' >&2
exit 42
BUFFER
chmod +x "$workdir/fault/mbuffer"
remote_bin="/var/tmp/$dst-fault"
remote "mkdir -p $remote_bin; cat > $remote_bin/mbuffer; chmod +x $remote_bin/mbuffer" < "$workdir/fault/mbuffer"
# Only change the receiving pipeline's environment; authentication and probes
# still use the real SSH binary and normal receiver environment.
cat > "$workdir/fault/ssh" <<SSH
#!/bin/sh
case "\$*" in
    *iocell-receive.XXXXXX*)
        peer="\$1"; shift
        exec /usr/bin/ssh "\$peer" "env PATH=$remote_bin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin \$*"
        ;;
    *) exec /usr/bin/ssh "\$@" ;;
esac
SSH
chmod +x "$workdir/fault/ssh"
read_remote () {
    remote "zfs set mountpoint=/var/tmp/$dst-received $dst/iocell; zfs mount $dst/iocell 2>/dev/null || :; zfs mount $dst/iocell/jails/$u/root 2>/dev/null || :; p=\$(zfs get -H -o value mountpoint $dst/iocell/jails/$u/root); cat \"\$p/marker\""
}
for mode in plain buffered csh-buffered; do
    if remote "zfs list $dst/iocell" >/dev/null 2>&1; then
        remote "zfs destroy -r $dst/iocell"
    fi
    echo "$mode-first" > "$mp/marker"
    case "$mode" in plain) test_path="$workdir/plain:$PATH" ;;
        csh-buffered) test_path="$workdir/csh:$PATH" ;;
        *) test_path="$PATH" ;; esac
    PATH="$test_path" iocell send -r -h "${peer#*@}" -u "${peer%@*}" "$dst" > "$workdir/$mode-full.log" 2>&1
    [ "$(read_remote)" = "$mode-first" ]
    base=$(zfs list -H -d1 -t snapshot -o name -s creation "$src/iocell" | grep "^$src/iocell@" | tail -1)
    receiver_guid=$(remote "zfs get -H -o value guid $dst/iocell/jails/$u/root")
    echo "$mode-second-full" > "$mp/marker"
    status=0
    PATH="$test_path" iocell send -r -h "${peer#*@}" -u "${peer%@*}" "$dst" \
        > "$workdir/$mode-repeat-full.log" 2>&1 || status=$?
    [ "$status" != 0 ]
    grep -q 'transfer failed' "$workdir/$mode-repeat-full.log"
    [ "$(read_remote)" = "$mode-first" ]
    [ "$(remote "zfs get -H -o value guid $dst/iocell/jails/$u/root")" = "$receiver_guid" ]
    [ "$(cat "$mp/marker")" = "$mode-second-full" ]
    retained=$(awk '/snapshot retained:/ {print $NF}' "$workdir/$mode-repeat-full.log")
    zfs list -t snapshot "$retained" >/dev/null
    echo "PASS: real remote $mode second full receive fails with source/receiver data and GUID intact"
    echo "$mode-incremental" > "$mp/marker"
    zfs snapshot -r "$src/iocell@$mode-inc1"
    PATH="$test_path" iocell send -r -h "${peer#*@}" -u "${peer%@*}" \
        -i "$base" -i "$src/iocell@$mode-inc1" "$dst" > "$workdir/$mode-i.log" 2>&1
    [ "$(read_remote)" = "$mode-incremental" ]
    echo "$mode-middle" > "$mp/marker"; zfs snapshot -r "$src/iocell@$mode-inc2"
    echo "$mode-inclusive" > "$mp/marker"; zfs snapshot -r "$src/iocell@$mode-inc3"
    PATH="$test_path" iocell send -r -h "${peer#*@}" -u "${peer%@*}" \
        -I "$src/iocell@$mode-inc1" -I "$src/iocell@$mode-inc3" "$dst" > "$workdir/$mode-I.log" 2>&1
    [ "$(read_remote)" = "$mode-inclusive" ]
    remote "zfs list -t snapshot $dst/iocell@$mode-inc2" >/dev/null
    echo "PASS: real remote $mode full, -i and -I streams preserve content/snapshots"
done
# Start each fault case with a fresh receiver: a full stream does not silently
# destroy the snapshots of an existing replica.
for fault in local-buffer remote-buffer; do
    remote "zfs destroy -r $dst/iocell"
    if [ "$fault" = remote-buffer ]; then
        # Local buffer must succeed: only retain the SSH wrapper in this path.
        mkdir -p "$workdir/remote-only"
        cp "$workdir/fault/ssh" "$workdir/remote-only/ssh"
        test_path="$workdir/remote-only:$PATH"
    else
        mkdir -p "$workdir/local-only"
        cp "$workdir/fault/mbuffer" "$workdir/local-only/mbuffer"
        test_path="$workdir/local-only:$PATH"
    fi
    status=0
    PATH="$test_path" iocell send -r -h "${peer#*@}" -u "${peer%@*}" "$dst" \
        > "$workdir/$fault.log" 2>&1 || status=$?
    [ "$status" = 42 ]
    grep -q 'injected real buffer failure' "$workdir/$fault.log"
    retained=$(awk '/snapshot retained:/ {print $NF}' "$workdir/$fault.log")
    zfs list -t snapshot "$retained" >/dev/null
    [ "$(zfs get -H -o value guid "$root")" = "$guid" ]
    [ "$(iocell get pool default)" = "$src" ]
    echo "PASS: real $fault failure propagates and source is retained"
done
# Same pool names on different hosts must not be mistaken for self-send.
remote "zfs set mountpoint=/var/tmp/$dst-last $dst/iocell"
remote "truncate -s 512M /var/tmp/$src.vdev; zpool create -O mountpoint=none $src /var/tmp/$src.vdev"
iocell send -r -h "${peer#*@}" -u "${peer%@*}" "$src" > "$workdir/same-name.log" 2>&1
[ "$(remote "p=\$(zfs get -H -o value mountpoint $src/iocell/jails/$u/root); cat \"\$p/marker\"")" = "$mode-inclusive" ]
echo 'PASS: remote source and destination may use the same pool name'
# Remote cleanup must not delete a backup in a same-named local pool.
remote "zfs destroy -r $dst/iocell"
zfs create -o mountpoint="$workdir/local-shadow" "$dst/iocell"
echo local-preserved > "$workdir/local-shadow/marker"
zfs snapshot "$dst/iocell@ioc-send-local-keep"
local_guid=$(zfs get -H -o value guid "$dst/iocell@ioc-send-local-keep")
echo remote-clean > "$mp/marker"
iocell send -c -r -h "${peer#*@}" -u "${peer%@*}" "$dst" > "$workdir/remote-clean.log" 2>&1
[ "$(read_remote)" = remote-clean ]
[ "$(zfs get -H -o value guid "$dst/iocell@ioc-send-local-keep")" = "$local_guid" ]
[ "$(cat "$workdir/local-shadow/marker")" = local-preserved ]
echo 'PASS: remote clean send preserves same-named local backup snapshot/data'
base=$(zfs list -H -d1 -t snapshot -o name -s creation "$src/iocell" | grep "^$src/iocell@ioc-send-" | tail -1)
[ -n "$base" ] || { echo 'FAIL: remote -c deleted its common replication base'; exit 1; }
[ "$(zfs list -H -d1 -t snapshot -o name "$src/iocell" | grep -c '@ioc-send-')" = 1 ]
zfs list "$src/iocell@plain-inc1" >/dev/null
[ "$(zfs get -H -o value guid "$base")" = \
    "$(remote "zfs get -H -o value guid $dst/iocell@${base#*@}")" ]
status=0
iocell send -c -r -h "${peer#*@}" -u "${peer%@*}" "$dst" \
    > "$workdir/failed-clean.log" 2>&1 || status=$?
[ "$status" != 0 ]
zfs list "$base" >/dev/null
[ "$(read_remote)" = remote-clean ]
echo 'PASS: refused clean full send retains the previous common base and receiver data'
echo after-clean > "$mp/marker"
zfs snapshot -r "$src/iocell@after-clean"
iocell send -r -h "${peer#*@}" -u "${peer%@*}" -i "$base" \
    -i "$src/iocell@after-clean" "$dst" > "$workdir/after-clean.log" 2>&1
[ "$(read_remote)" = after-clean ]
echo 'PASS: remote clean send retains a common GUID and permits the next incremental send'
zpool status -x
remote zpool status -x
