#!/bin/sh
# Real CLI/property setter: values are data, not eval programs or split fields.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-cmd
. ./tests/cli-dispatch.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-set-values.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; uuid=11111111-1111-1111-1111-111111111111
iocroot="$workdir/iocell"
mkdir -p "$iocroot/jails/$uuid" "$workdir/values"
CONF_NET=''; CONF_JAIL=exec_start; CONF_RCTL=''
CONF_CUSTOM='notes owner boot tag'; CONF_SYNC=''; CONF_FTP=''; CONF_GIT=''; CONF_ZFS=''
__find_jail () { echo "tank/iocell/jails/$uuid"; }
__check_name () { echo "$uuid"; }
__get_jail_prop () {
    case "$1" in type) echo basejail ;; mountpoint) echo "$iocroot/jails/$uuid" ;; esac
}
__ucl_set () { printf '%s' "$3" > "$workdir/values/$2"; }
failed=0
check_value () {
    label=$1; property=$2; value=$3; status=0
    rm -f "$workdir/values/$property"
    ( ioc_test_dispatch set "$property=$value" "$uuid" ) > "$workdir/$label.log" 2>&1 || status=$?
    printf '%s' "$value" > "$workdir/expected"
    if [ "$status" != 0 ] || ! cmp -s "$workdir/expected" "$workdir/values/$property"; then
        echo "FAIL: set $label lost the literal value (status $status)"
        failed=1
    else
        echo "PASS: set $label"
    fi
}
check_value repeated-equals owner 'alpha=beta=gamma'
check_value command-equals exec_start 'env FOO=one=two /bin/sh /etc/rc'
check_value note-spacing notes 'alpha  beta=gamma'
check_value apostrophe notes "worker's=value"
check_value literal-program notes '$(false); value=literal'
check_value newline owner 'first
second=value'
for command in set get create; do
    status=0
    (
        tag=default
        __export_props "$command" tag=default
        if [ "$command" = create ]; then [ "$tag" != default ]
        else [ "$tag" = default ]; fi
    ) > "$workdir/tag-$command.log" 2>&1 || status=$?
    if [ "$status" = 0 ]; then echo "PASS: reserved tag predicate for $command"
    else echo "FAIL: reserved tag predicate for $command"; failed=1; fi
done
status=0
( __set_jail_prop owner "$uuid" ) > "$workdir/malformed.log" 2>&1 || status=$?
if [ "$status" = 0 ]; then
    echo 'FAIL: backend accepted a property without equals'; failed=1
else
    echo 'PASS: backend rejects a property without equals'
fi
exit "$failed"
