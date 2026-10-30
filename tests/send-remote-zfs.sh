#!/bin/sh
# Opt-in native SSH replication checks, including real optional mbuffer.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname -s)" = FreeBSD ] && [ "$(id -u)" = 0 ] || exit 1
: "${IOC_TEST_POOL:?Set the active disposable pool}"
: "${IOC_TEST_REMOTE:?Set root@private-disposable-FreeBSD-receiver}"
peer="$IOC_TEST_REMOTE"
iocell () { env PATH="$PATH" sh ./iocell "$@"; }
remote () { /usr/bin/ssh "$peer" "$@"; }
original=$(iocell get pool default)
[ "$original" = "$IOC_TEST_POOL" ]
[ "$(remote uname -s)" = FreeBSD ]
command -v mbuffer >/dev/null
remote /usr/bin/which -s mbuffer
workdir=$(mktemp -d /var/tmp/iocell-remote-safety.XXXXXX)
src="iocrsrc$$"; dst="iocrrx$$"; activated=0
cleanup () {
    status=$?
    trap - EXIT
    if [ "$activated" = 1 ]; then
        iocell activate "$original" > "$workdir/restore.log" 2>&1 || status=1
    fi
    echo "Retained remote safety logs/vdevs: $workdir"
    echo "Retained pools: local $src $dst; receiver $dst"
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
mkdir "$workdir/plain" "$workdir/fault"
# Force the no-buffer branch even though mbuffer is installed for later cases.
cat > "$workdir/plain/which" <<'WHICH'
#!/bin/sh
[ "$*" != '-s mbuffer' ] || exit 1
exec /usr/bin/which "$@"
WHICH
chmod +x "$workdir/plain/which"
# A real buffer completing a real stream, then reporting a failure.
cat > "$workdir/fault/mbuffer" <<'BUFFER'
#!/bin/sh
/usr/local/bin/mbuffer "$@" || exit $?
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
for mode in plain buffered; do
    if remote "zfs list $dst/iocell" >/dev/null 2>&1; then
        remote "zfs destroy -r $dst/iocell"
    fi
    echo "$mode-first" > "$mp/marker"
    if [ "$mode" = plain ]; then test_path="$workdir/plain:$PATH"
    else test_path="$PATH"; fi
    PATH="$test_path" iocell send -r -h "${peer#*@}" -u "${peer%@*}" "$dst" > "$workdir/$mode-full.log" 2>&1
    [ "$(read_remote)" = "$mode-first" ]
    base=$(zfs list -H -d1 -t snapshot -o name -s creation "$src/iocell" | grep "^$src/iocell@" | tail -1)
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
    if PATH="$test_path" iocell send -r -h "${peer#*@}" -u "${peer%@*}" "$dst" > "$workdir/$fault.log" 2>&1; then
        echo "FAIL: $fault failure reported success" >&2; exit 1
    fi
    [ "$(zfs get -H -o value guid "$root")" = "$guid" ]
    [ "$(iocell get pool default)" = "$src" ]
    echo "PASS: real $fault failure propagates and source is retained"
done
# Same pool names on different hosts must not be mistaken for self-send.
remote "zfs set mountpoint=/var/tmp/$dst-last $dst/iocell"
remote "truncate -s 512M /var/tmp/$src.vdev; zpool create -O mountpoint=none $src /var/tmp/$src.vdev"
iocell send -r -h "${peer#*@}" -u "${peer%@*}" "$src" > "$workdir/same-name.log" 2>&1
[ "$(remote "p=\$(zfs get -H -o value mountpoint $src/iocell/jails/$u/root); cat \"\$p/marker\"")" = buffered-inclusive ]
echo 'PASS: remote source and destination may use the same pool name'
zpool status -x
remote zpool status -x
