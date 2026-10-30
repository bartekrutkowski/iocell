#!/bin/sh
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-console.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
uuid=11111111-1111-1111-1111-111111111111
__find_jail () { echo "tank/iocell/jails/$uuid"; }
__check_name () { echo "$uuid"; }
__get_jail_prop () {
    case "$1" in login_flags) echo '-f root' ;; exec_fib) echo 0 ;; esac
}
__is_running () { [ "$running" != yes ] || echo 1; }
__start_jail () {
    printf 'start <%s>\n' "$1" >> "$trace"
    [ "$1" = "$uuid" ] || return 43
    [ "$start_failure" != yes ] || return 42
}
jexec () { printf 'login %s\n' "$*" >> "$trace"; }
failed=0
for label in forced running stopped start-failure; do
    trace="$workdir/$label.trace"; : > "$trace"
    running=no; _force=1; start_failure=no; want=0
    case "$label" in running) running=yes ;; stopped) _force=0; want=1 ;;
        start-failure) start_failure=yes; want=42 ;; esac
    status=0
    ( __console example-tag ) > "$workdir/$label.log" 2>&1 || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: console $label status=$status expected=$want"; failed=1; continue
    fi
    if [ "$label" = forced ] && ! grep -Fx "start <$uuid>" "$trace" >/dev/null; then
        echo 'FAIL: forced console started the wrong identity'; failed=1; continue
    fi
    if [ "$label" = running ] && grep -q '^start ' "$trace"; then
        echo 'FAIL: running console unnecessarily started a jail'; failed=1; continue
    fi
    case "$label" in
        forced|running)
            grep -Fx "login ioc-$uuid login -f root" "$trace" >/dev/null || { failed=1; continue; } ;;
        *) if grep -q '^login ' "$trace"; then
            echo "FAIL: console $label attempted login"; failed=1; continue; fi ;;
    esac
    echo "PASS: console $label"
done
exit "$failed"
