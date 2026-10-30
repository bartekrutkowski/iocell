#!/bin/sh
# A real clone blocker or failed origin query must stop destroy with a reason.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-destroy-guard.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; _force=1
__find_jail () { echo tank/iocell/jails/fixture; }
__check_name () { echo fixture; }
__get_jail_prop () { echo basejail; }
__is_running () { :; }
zfs () {
    case " $* " in
        *' -rH '*)
            if [ "$query_error" = 1 ]; then
                printf '%s\t%s\n' tank/clone/root tank/iocell/jails/fixture/root@saved
            else
                return "$query_error"
            fi ;;
        *) echo - ;;
    esac
}
__destroy_func () { rm "$workdir/data"; }
failed=0
for query_error in 1 8 9; do
    echo preserved > "$workdir/data"
    status=0
    ( __destroy_jail fixture ) > "$workdir/log" 2>&1 || status=$?
    if [ "$query_error" = 1 ]; then reason='dependent clones'; label=clone-blocker
    else reason='cannot inspect dependent clones'; label="query-error-$query_error"; fi
    if [ "$status" != "$query_error" ] || [ ! -e "$workdir/data" ] || \
        ! grep -q "$reason" "$workdir/log"; then
        echo "FAIL: $label did not retain data and report its reason"; failed=1
    else
        echo "PASS: $label retains data with a diagnostic"
    fi
done
exit "$failed"
