#!/bin/sh
# Preserve kernel errors while accepting a successful empty rule listing.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-rctl
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-rctl.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
CONF_RCTL=maxproc
__find_jail () { echo tank/iocell/jails/fixture; }
__check_name () { echo fixture; }
__get_jail_prop () {
    case "$1" in rlimits) echo on ;; maxproc) echo "$value" ;; tag) echo fixture ;; esac
}
__is_running () { echo 11; }
jls () { echo 11; }
cpuset () { echo 'jail 11 mask: 0'; }
rctl () {
    case "$*" in
        ''|-h)
            [ "$mode" != list-error ] || return 42
            [ "$mode" != verify-error ] || return 46
            if [ "$mode" = leftover ]; then echo 'jail:ioc-fixture:maxproc:deny=1'; fi ;;
        '-r jail:ioc-fixture') [ "$mode" != remove-error ] || return 43 ;;
        '-a jail:ioc-fixture:maxproc:deny=1') [ "$mode" != apply-error ] || return 44 ;;
        '-hu jail:ioc-fixture') [ "$mode" != use-error ] || return 45
            echo cputime=0 ;;
        *) echo "unexpected rctl call: $*" >&2; return 99 ;;
    esac
}
failed=0
for mode in list-empty list-error removed remove-error verify-error leftover invalid apply-error use-error all-use-error applied; do
    value=1:deny; status=0; want=0
    case "$mode" in list-error) want=42 ;; remove-error) want=43 ;;
        apply-error) want=44 ;; use-error|all-use-error) want=45 ;;
        verify-error) want=46 ;; leftover|invalid) want=1 ;; esac
    (
        case "$mode" in
            list-*) __rctl_list '' ;;
            removed|remove-error|verify-error|leftover) __rctl_uncap fixture ;;
            invalid) value=malformed; __rctl_limits fixture ;;
            apply-error|applied) __rctl_limits fixture ;;
            use-error) __rctl_inuse fixture ;;
            all-use-error) mode=use-error
                __find_jail () { echo tank/iocell/jails/11111111-1111-1111-1111-111111111111; }
                __rctl_inuse_all ;;
        esac
    ) > "$workdir/$mode.log" 2>&1 || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: rctl $mode status=$status expected=$want"; failed=1
    elif [ "$want" != 0 ] && grep -q ' OK' "$workdir/$mode.log"; then
        echo "FAIL: rctl $mode falsely reported successful application"; failed=1
    else echo "PASS: rctl $mode preserves meaningful status"; fi
done
exit "$failed"
