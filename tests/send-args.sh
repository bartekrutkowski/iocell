#!/bin/sh
# Parsed snapshot operands remain individual arguments; no eval/word splitting.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-send-args.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=src
which () { return 1; }
ssh () { return 0; }
uuidgen () { echo 11111111-1111-1111-1111-111111111111; }
date () { echo 2026-01-01; }
jls () { [ "$mode" != jail-query ] || { echo 'injected jail query failure' >&2; return 12; }; }
__send_stream () { printf '%s\n' "$@" >> "$trace"; }
__activate () { pool=$1; }
uclcmd () { echo dst; }
zfs () {
    case "$1" in
        get) echo available ;;
        destroy) rm "$workdir/source" ;;
        snapshot) echo snapshot >> "$trace" ;;
    esac
}
failed=0
for mode in full incremental inclusive jail-query; do
    trace="$workdir/$mode.trace"; : > "$trace"
    echo preserved > "$workdir/source"; status=0
    case "$mode" in
        full) set -- dst
            printf '%s\n' snapshot dst '' 0 -R \
                src/iocell@ioc-send-2026-01-01-11111111-1111-1111-1111-111111111111 \
                > "$workdir/expected" ;;
        incremental|inclusive)
            opt=i; [ "$mode" != inclusive ] || opt=I
            set -- -r -h peer -u root "-$opt" 'relative@old point' \
                "-$opt" 'src/iocell@new point' dst
            printf '%s\n' dst root@peer 0 "-R$opt" 'relative@old point' \
                'src/iocell@new point' > "$workdir/expected" ;;
        jail-query) set -- -m dst; : > "$workdir/expected" ;;
    esac
    ( set +e; __send "$@" ) > "$workdir/$mode.log" 2>&1 || status=$?
    want=0; [ "$mode" != jail-query ] || want=12
    if [ "$status" != "$want" ] || ! cmp -s "$trace" "$workdir/expected" || \
        [ ! -f "$workdir/source" ]; then
        echo "FAIL: send parsing $mode status=$status"; failed=1
        cat "$workdir/$mode.log"
        diff -u "$workdir/expected" "$trace" || :
    else echo "PASS: send parsing $mode"; fi
done
_clean=preserved; _remotehost=preserved; _from=preserved; _dest=preserved
__validate_send_args -r -h peer -u root -i source@a -i source@b dst
if [ "$_clean:$_remotehost:$_from:$_dest" != preserved:preserved:preserved:preserved ]; then
    echo 'FAIL: syntax validation leaked parsed state into its caller'; failed=1
else echo 'PASS: send syntax validation does not retain caller-visible parse state'; fi
exit "$failed"
