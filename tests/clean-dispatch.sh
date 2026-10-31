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
for mode in combined clustered all-first all-last all-repeat failure empty force-only direct-empty direct-force; do
    trace="$workdir/$mode.actions"; : > "$trace"; status=0; want=0
    case "$mode" in
        combined) set -- -j -t -f; expected='jails:1
templates:1' ;;
        clustered) set -- -jtf; expected='jails:1
templates:1' ;;
        all-first) set -- -a -j -f; expected='all:1' ;;
        all-last) set -- -j -t -f -a; expected='all:1' ;;
        all-repeat) set -- -a -a; expected='all:0' ;;
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
for action in all releases jails; do
    for fault in native stop; do
        state="$workdir/$action-$fault"; mkdir -p "$state/tree"
        echo preserved > "$state/tree/canary"
        trace="$state/trace"; : > "$trace"; status=0; want=42
        [ "$fault" != stop ] || want=43
        (
            . ./lib/ioc-zfs
            iocroot="$state/tree"; pool=tank; _force=1
            __stop_jail_all () { [ "$fault" != stop ] || return 43; }
            __clean_snapshots () { :; }
            zfs () { jobs -p > "$state/pids"; echo "$*" >> "$trace"; return 42; }
            "__clean_$action"
        ) > "$state/log" 2>&1 || status=$?
        if [ "$status" != "$want" ] || [ ! -f "$state/tree/canary" ]; then
            echo "FAIL: cleanup $action ignored $fault failure or removed data"; failed=1
        elif [ "$fault" = stop ] && [ -s "$trace" ]; then
            echo "FAIL: cleanup $action destroyed datasets after stop failure"; failed=1
        else echo "PASS: cleanup $action propagates $fault failure"; fi
        if [ -f "$state/pids" ]; then
            while IFS= read -r pid; do
                if kill -0 "$pid" 2>/dev/null; then
                    echo 'FAIL: cleanup left its spinner alive'; kill "$pid" || :; failed=1
                fi
            done < "$state/pids"
        fi
    done
done
exit "$failed"
