#!/bin/sh
# Execute the real receiver command through csh; only ZFS/buffering are doubles.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
if ! command -v csh >/dev/null; then
    echo 'SKIP: csh unavailable'; exit 0
fi
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-send-csh.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
mkdir "$workdir/bin"
export CSH_REAL_MKTEMP="$(command -v mktemp)" CSH_TEMPS="$workdir/temps"
cat > "$workdir/bin/zfs" <<'ZFS'
#!/bin/sh
[ "$*" = 'receive -F destination/iocell' ] || exit 99
cat > "$CSH_RECEIVED"
[ "$CSH_FAULT" != receiver ] || { echo 'fixture receiver failure' >&2; exit 42; }
ZFS
cat > "$workdir/bin/mbuffer" <<'BUFFER'
#!/bin/sh
[ "$*" = '-q -s 128k -m 1G' ] || exit 99
cat
[ "$CSH_FAULT" != buffer ] || { echo 'fixture buffer failure' >&2; exit 43; }
BUFFER
cat > "$workdir/bin/mktemp" <<'TEMP'
#!/bin/sh
path=$("$CSH_REAL_MKTEMP" "$@") || exit $?
printf '%s\n' "$path" >> "$CSH_TEMPS"
printf '%s\n' "$path"
TEMP
chmod +x "$workdir/bin/"*
export PATH="$workdir/bin:$PATH"
ssh () { shift; command csh -f -c "$*"; }
printf '%s\n' "payload with 'quotes', spaces and = signs" second-line > "$workdir/input"
for mode in plain buffered receiver buffer; do
    export CSH_FAULT="$mode" CSH_RECEIVED="$workdir/$mode.received"
    buffered=1; want=0; status=0; : > "$CSH_TEMPS"
    case "$mode" in plain) buffered=0 ;; receiver) want=42 ;; buffer) want=43 ;; esac
    __send_receive destination root@receiver "$buffered" < "$workdir/input" \
        > "$workdir/$mode.out" 2> "$workdir/$mode.err" || status=$?
    [ "$status" = "$want" ]
    cmp "$workdir/input" "$CSH_RECEIVED"
    case "$mode" in receiver|buffer) grep -Fq "fixture $mode failure" "$workdir/$mode.err" ;; esac
    while IFS= read -r temp; do [ ! -e "$temp" ]; done < "$CSH_TEMPS"
    echo "PASS: csh $mode executes receiver, preserves bytes/status and cleans temporary state"
done
