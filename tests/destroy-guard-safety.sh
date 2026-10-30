#!/bin/sh
# All dependency-query errors must stop the consumer before destruction.
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
__check_children () { return "$query_error"; }
zfs () { echo -; }
__destroy_func () { rm "$workdir/data"; }
failed=0
for query_error in 1 8 9; do
    echo preserved > "$workdir/data"
    status=0
    ( set +e; __destroy_jail fixture ) > "$workdir/log" 2>&1 || status=$?
    if [ "$status" -ne "$query_error" ] || [ ! -e "$workdir/data" ]; then
        echo "FAIL: dependency-query error $query_error did not stop destroy"
        failed=1
    else
        echo "PASS: dependency-query error $query_error retains data"
    fi
done
exit "$failed"
