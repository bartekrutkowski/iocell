#!/bin/sh
# Public start dispatch continues all targets and preserves the first failure.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
. ./lib/ioc-rc
. ./lib/ioc-cmd
. ./tests/cli-dispatch.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-start-dispatch.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
__start_jail () {
    printf '%s %s\n' "$1" "$_force" >> "$trace"
    case "$mode:$1" in
        first:alpha|multiple:alpha|forced:alpha|reboot-first:alpha) return 42 ;;
        last:gamma|multiple:beta) return 17 ;;
        exiting:alpha) exit 43 ;;
    esac
    return 0
}
failed=0
for mode in success first last multiple exiting forced; do
    trace="$workdir/$mode.trace"; : > "$trace"; status=0; want=0; force=0
    case "$mode" in first|multiple|forced) want=42 ;; last) want=17 ;; exiting) want=43 ;; esac
    set -- alpha beta gamma
    if [ "$mode" = forced ]; then set -- -f "$@"; force=1; fi
    ( ioc_test_dispatch start "$@" ) > "$workdir/$mode.log" 2>&1 || status=$?
    printf 'alpha %s\nbeta %s\ngamma %s\n' "$force" "$force" "$force" > "$workdir/expected"
    if [ "$status" != "$want" ] || ! cmp -s "$trace" "$workdir/expected"; then
        echo "FAIL: start $mode lost status ($status/$want), targets or force flag"; failed=1
    else echo "PASS: start $mode attempts all targets and preserves first failure"; fi
done
# Hard reboot/restart are existing fail-fast callers of the startup helper.
__stop_jail () { return 0; }
mode=reboot-first; _force=0
for command in reboot restart; do
    trace="$workdir/$command.trace"; : > "$trace"; status=0
    ( ioc_test_dispatch "$command" alpha beta ) > "$workdir/$command.log" 2>&1 || status=$?
    printf 'alpha 0\n' > "$workdir/expected"
    if [ "$status" != 42 ] || ! cmp -s "$trace" "$workdir/expected"; then
        echo "FAIL: $command lost its startup failure or fail-fast policy"; failed=1
    else echo "PASS: $command preserves its startup failure and fail-fast policy"; fi
done
exit "$failed"
