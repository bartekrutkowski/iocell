#!/bin/sh
# Public lifecycle commands attempt every target and keep the first failure.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
. ./lib/ioc-rc
. ./lib/ioc-cmd
. ./tests/cli-dispatch.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-start-dispatch.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
operation () {
    printf '%s %s %s\n' "$1" "$2" "${_force:-0}" >> "$trace"
    case "$mode:$2" in
        first:alpha|multiple:alpha|forced:alpha) return 42 ;;
        last:gamma|multiple:beta) return 17 ;;
        exiting:alpha) exit 43 ;;
    esac
    return 0
}
__start_jail () { operation start "$1"; }
__stop_jail () { operation stop "$1"; }
__reboot_jail () { operation reboot "$1"; }
__restart_jail () { operation soft "$1"; }
failed=0
for variant in start stop reboot restart reboot-soft restart-soft forced; do
    _force=0; force=0
    case "$variant" in
        start|forced) backend=start ;; stop) backend=stop ;;
        reboot|restart) backend=reboot ;; *) backend=soft ;;
    esac
    for mode in success first last multiple exiting; do
        [ "$variant" != forced ] || mode=forced
        trace="$workdir/$variant-$mode.trace"; : > "$trace"; status=0; want=0
        case "$mode" in first|multiple|forced) want=42 ;; last) want=17 ;; exiting) want=43 ;; esac
        case "$variant" in
            forced) set -- start -f; force=1 ;;
            reboot-soft) set -- reboot -s ;; restart-soft) set -- restart -s ;;
            *) set -- "$variant" ;;
        esac
        ( ioc_test_dispatch "$@" alpha beta gamma ) > "$workdir/$variant-$mode.log" 2>&1 || status=$?
        printf '%s alpha %s\n%s beta %s\n%s gamma %s\n' \
            "$backend" "$force" "$backend" "$force" "$backend" "$force" > "$workdir/expected"
        if [ "$status" != "$want" ] || ! cmp -s "$trace" "$workdir/expected"; then
            echo "FAIL: $variant $mode lost status ($status/$want), ordered targets or force flag"; failed=1
        else echo "PASS: $variant $mode attempts all targets and preserves first failure"; fi
        [ "$variant" != forced ] || break
    done
done
exit "$failed"
