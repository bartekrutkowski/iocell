#!/bin/sh
# Keep discovery, property reads and rc selection real: a dataset is not a name.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-rc
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-rc.XXXXXX")
fixed="/tmp/iocell.$$"
[ ! -e "$fixed" ] && [ ! -L "$fixed" ] || exit 1
trap 'rm -f "$fixed"; rm -rf "$workdir"' EXIT
: > "$workdir/canary"
ln -s "$workdir/canary" "$fixed"
: > "$workdir/temps"
mktemp () {
    temp=$(command mktemp "$@") || return $?
    echo "$temp" >> "$workdir/temps"
    printf '%s\n' "$temp"
}
pool=tank; hostid=fixture-host
first=11111111-1111-1111-1111-111111111111
second=22222222-2222-2222-2222-222222222222
foreign=33333333-3333-3333-3333-333333333333
disabled=44444444-4444-4444-4444-444444444444
mkdir "$workdir/running"
for uuid in "$first" "$second" "$foreign" "$disabled"; do
    mkdir "$workdir/$uuid"
    boot=on; owner="$hostid"; priority=20
    case "$uuid" in
        "$first") priority=10 ;;
        "$foreign") owner=another-host ;;
        "$disabled") boot=off ;;
    esac
    printf 'tag=rc-%s\nhost_hostuuid=%s\nboot=%s\nhostid=%s\npriority=%s\n' \
        "$uuid" "$uuid" "$boot" "$owner" "$priority" > "$workdir/$uuid/config"
done
fault=none
zfs () {
    case "$*" in
        "list -d1 -rH -o name tank/iocell/jails tank/iocell/templates")
            if [ "$fault" = enumeration ]; then
                echo 'injected rc discovery failure' >&2; return 42
            fi
            printf '%s\n' tank/iocell/jails "tank/iocell/jails/$second" \
                "tank/iocell/jails/$foreign" "tank/iocell/jails/$first" \
                "tank/iocell/jails/$disabled" tank/iocell/templates ;;
        'get -H -o value mountpoint tank/iocell/jails/'*)
            for target; do :; done
            [ -d "$workdir/${target##*/}" ] || return 99
            echo "$workdir/${target##*/}" ;;
        *) echo "unexpected ZFS call: $*" >&2; return 99 ;;
    esac
}
uclcmd () {
    [ "$1" = get ] && [ "$2" = -qf ] && [ "$#" = 4 ] || return 99
    awk -F= -v key="$4" '$1 == key {print $2; found=1}
        END {if (!found) print "null"}' "$3"
}
jls () {
    if [ "$#" = 3 ] && [ "$1" = -j ] && [ "$3" = jid ]; then
        [ -f "$workdir/running/${2#ioc-}" ] || return 1
        echo 1
    elif [ "$#" = 0 ]; then
        # Like native jls, the default display need not contain the full path.
        for marker in "$workdir/running/"*; do
            [ -f "$marker" ] || continue
            printf '1 fixture %.30s\n' "$workdir/${marker##*/}"
        done
    else
        echo "unexpected jls call: $*" >&2; return 99
    fi
}
__start_jail () {
    [ "$fault" != backend-exit ] || exit 42
    [ "$#" = 1 ] && [ -f "$workdir/$1/config" ] || return 99
    touch "$workdir/running/$1"
    echo "$1" >> "$workdir/actions"
}
__stop_jail () {
    [ "$#" = 2 ] && [ "$2" = "tank/iocell/jails/$1" ] || return 99
    rm "$workdir/running/$1"
    echo "$1" >> "$workdir/actions"
}
failed=0
for action in boot shutdown; do
    : > "$workdir/actions"; status=0
    ( __rc_jails "$action" ) > "$workdir/$action.log" 2>&1 || status=$?
    if [ "$action" = boot ]; then
        printf '%s\n' "$first" "$second" > "$workdir/expected"
        present=yes
    else
        printf '%s\n' "$second" "$first" > "$workdir/expected"
        present=no
    fi
    if [ "$status" != 0 ] || ! cmp -s "$workdir/actions" "$workdir/expected"; then
        echo "FAIL: rc $action did not select eligible UUIDs in priority order"
        failed=1; continue
    fi
    for uuid in "$first" "$second"; do
        if [ "$present" = yes ]; then [ -f "$workdir/running/$uuid" ]
        else [ ! -e "$workdir/running/$uuid" ]; fi || exit 1
    done
    [ ! -e "$workdir/running/$foreign" ] && \
        [ ! -e "$workdir/running/$disabled" ] || exit 1
    echo "PASS: rc $action uses real discovery and properties in priority order"
done
if [ -s "$workdir/canary" ] || [ ! -L "$fixed" ]; then
    echo 'FAIL: rc used the predictable PID path or followed its symlink'
    failed=1
else
    echo 'PASS: rc ignores a preexisting predictable-path symlink'
fi
rm -f "$fixed"
printf '5,%s\n' "$disabled" > "$fixed"
: > "$workdir/actions"; status=0
( __rc_jails boot ) > "$workdir/stale.log" 2>&1 || status=$?
printf '%s\n' "$first" "$second" > "$workdir/expected"
if [ "$status" != 0 ] || ! cmp -s "$workdir/actions" "$workdir/expected"; then
    echo 'FAIL: rc included stale predictable-file contents in the boot order'
    failed=1
else
    echo 'PASS: rc ignores stale predictable-file contents'
fi
fault=backend-exit; status=0
( __rc_jails boot ) > "$workdir/backend.log" 2>&1 || status=$?
[ "$status" = 42 ] || { echo 'FAIL: rc lost an exiting backend failure'; failed=1; }
fault=none; hostid=no-matching-host; : > "$workdir/actions"; status=0
( __rc_jails boot ) > "$workdir/empty.log" 2>&1 || status=$?
if [ "$status" != 0 ] || [ -s "$workdir/actions" ] || \
    ! grep -q 'no jails found' "$workdir/empty.log"; then
    echo 'FAIL: rc empty selection did not exit cleanly'; failed=1
else echo 'PASS: rc empty selection succeeds without lifecycle work'; fi
if [ ! -s "$workdir/temps" ]; then
    echo 'FAIL: rc did not allocate private temporary boot lists'; failed=1
else
    while IFS= read -r temp; do
        [ ! -e "$temp" ] || { echo 'FAIL: rc leaked its temporary boot list'; failed=1; }
    done < "$workdir/temps"
    echo 'PASS: rc removes private boot lists on normal, empty and exiting paths'
fi
fault=enumeration; : > "$workdir/actions"; status=0
( __rc_jails boot ) > "$workdir/enumeration.log" 2>&1 || status=$?
if [ "$status" != 42 ] || [ -s "$workdir/actions" ] || \
    ! grep -q 'injected rc discovery failure' "$workdir/enumeration.log"; then
    echo 'FAIL: rc discovery failure must propagate without starting a jail'
    failed=1
else
    echo 'PASS: rc discovery failure propagates before lifecycle actions'
fi
exit "$failed"
