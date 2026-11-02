#!/bin/sh
# Keep real command wrappers; replace only kernel/pkg execution boundaries.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-exec-pkg.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
__find_jail () {
    if [ "$1" = ALL ]; then
        printf 'tank/iocell/jails/%s\n' "$first" "$second"
        [ "$mode" != query ] || return 41
    else
        [ "$mode" != single-query ] || return 41
        echo "tank/iocell/jails/$1"
    fi
}
__check_name () { echo "${2##*/}"; [ "$mode" != name-query ] || return 44; }
__get_jail_prop () { [ "$mode" != fib-query ] || return 45; echo 0; }
jls () { echo 11; }
first=11111111-1111-1111-1111-111111111111
second=22222222-2222-2222-2222-222222222222
jexec () {
    printf '<%s>\n' "$@" >> "$trace"
    case "$mode:$*" in
        first:*"ioc-$first"*) return 42 ;;
        multiple:*"ioc-$first"*) return 42 ;;
        multiple:*"ioc-$second"*) return 43 ;;
    esac
    return 0
}
pkg () { printf '<%s>\n' "$@" >> "$trace"; return "$pkg_status"; }
failed=0
for mode in success first multiple query single-query name-query fib-query; do
    trace="$workdir/$mode.trace"; : > "$trace"; status=0; want=0
    case "$mode" in first|multiple) want=42 ;; name-query) want=44 ;;
        fib-query) want=45 ;; *query) want=41 ;; esac
    target=ALL
    case "$mode" in *-query) target="$first" ;; esac
    ( __exec "$target" /bin/echo 'two words' ) > "$workdir/$mode.log" 2>&1 || status=$?
    : > "$workdir/expected"
    if [ "$want" != 41 ] && [ "$want" != 44 ] && [ "$want" != 45 ]; then
        printf '<ioc-%s>\n</bin/echo>\n<two words>\n' "$first" > "$workdir/expected"
        printf '<ioc-%s>\n</bin/echo>\n<two words>\n' "$second" >> "$workdir/expected"
    fi
    if [ "$status" != "$want" ] || ! cmp -s "$trace" "$workdir/expected"; then
        echo "FAIL: exec ALL $mode lost failure, target or payload boundaries"; failed=1
    else echo "PASS: exec ALL $mode preserves status, targets and payload"; fi
done
mode=pkg
for pkg_status in 0 47; do
    trace="$workdir/pkg-$pkg_status.trace"; : > "$trace"; status=0
    ( __pkg_wrapper pkg "$first" query '%n %v' 'literal[1]*=value' ) \
        > "$workdir/pkg-$pkg_status.log" 2>&1 || status=$?
    printf '<-j>\n<11>\n<query>\n<%%n %%v>\n<literal[1]*=value>\n' > "$workdir/expected"
    if [ "$status" != "$pkg_status" ] || ! cmp -s "$trace" "$workdir/expected"; then
        echo 'FAIL: pkg wrapper split payload or lost status'; failed=1
    else echo "PASS: pkg wrapper preserves literal arguments and status $pkg_status"; fi
done
exit "$failed"
