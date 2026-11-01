#!/bin/sh
# Public start dispatch continues all targets and preserves the first failure.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
. ./lib/ioc-cmd
. ./tests/cli-dispatch.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-start-dispatch.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
__start_jail () {
    printf '%s %s\n' "$1" "$_force" >> "$trace"
    case "$mode:$1" in
        first:alpha|multiple:alpha|forced:alpha) return 42 ;;
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
exit "$failed"
