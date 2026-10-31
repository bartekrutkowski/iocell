#!/bin/sh
# Real validation, dispatch and cleanup scans; only namespace deletion is inert.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-cmd
. ./lib/ioc-zfs
. ./tests/cli-dispatch.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-clean-dispatch.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
__clean_jails () { echo "jails:$_force" >> "$trace"; }
__clean_templates () { echo "templates:$_force" >> "$trace"; }
__clean_all () { echo "all:$_force" >> "$trace"; }
__clean_releases () { echo "releases:$_force" >> "$trace"; return 42; }
failed=0
for mode in combined clustered failure empty force-only direct-empty direct-force; do
    trace="$workdir/$mode.actions"; : > "$trace"; status=0; want=0
    case "$mode" in
        combined) set -- -j -t -f; expected='jails:1
templates:1' ;;
        clustered) set -- -jtf; expected='jails:1
templates:1' ;;
        failure) set -- -r -j; expected='releases:0'; want=42 ;;
        empty|direct-empty) set --; expected=''; want=1 ;;
        *) set -- -f; expected=''; want=1 ;;
    esac
    (
        case "$mode" in direct-*) __clean "$@" ;; *) ioc_test_dispatch clean "$@" ;; esac
    ) > "$workdir/$mode.log" 2>&1 || status=$?
    if [ -n "$expected" ]; then printf '%s\n' "$expected" > "$workdir/expected"
    else : > "$workdir/expected"; fi
    if [ "$status" != "$want" ] || ! cmp -s "$trace" "$workdir/expected"; then
        echo "FAIL: clean $mode lost flags, status, or ran unintended cleanup"; failed=1
    else echo "PASS: clean dispatch $mode"; fi
done
exit "$failed"
