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
background_log=''
trap 'rm -f "$fixed"; [ -z "$background_log" ] || rm -f "$background_log"; rm -rf "$workdir"' EXIT
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
            case "$fault" in background-*) echo "tank/iocell/jails/$background"; return ;; esac
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
    case "$fault" in background-*)
        : > "$workdir/background-entered"
        attempts=0
        while [ ! -f "$workdir/background-release" ] && [ "$attempts" -lt 200 ]; do
            sleep 0.1; attempts=$((attempts + 1))
        done
        case "$fault" in background-success|background-cat-failure)
            echo 'completed background start'
            : > "$workdir/background-finished"
            return 0 ;;
        esac
        echo 'injected background failure' >&2
        : > "$workdir/background-finished"
        [ "$fault" != background-exit ] || exit 42
        return 43 ;;
    esac
    if [ "$1" = "$first" ]; then
        [ "$fault" != backend-exit ] || exit 42
        case "$fault" in backend-return|multiple) return 43 ;; esac
    fi
    [ "$fault" != multiple ] || return 44
    [ "$#" = 1 ] && [ -f "$workdir/$1/config" ] || return 99
    touch "$workdir/running/$1"
    echo "$1" >> "$workdir/actions"
}
__stop_jail () {
    if [ "$1" = "$second" ]; then
        [ "$fault" != backend-exit ] || exit 42
        [ "$fault" != backend-return ] || return 43
    fi
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
for action in boot shutdown; do
    for fault in backend-exit backend-return; do
        touch "$workdir/running/$first" "$workdir/running/$second"
        : > "$workdir/actions"; status=0; want=43
        [ "$fault" != backend-exit ] || want=42
        ( __rc_jails "$action" ) > "$workdir/$action-$fault.log" 2>&1 || status=$?
        if [ "$action" = boot ]; then echo "$second" > "$workdir/expected"
        else echo "$first" > "$workdir/expected"; fi
        if [ "$status" != "$want" ] || ! cmp -s "$workdir/actions" "$workdir/expected"; then
            echo "FAIL: rc $action $fault lost failure or skipped later jail"; failed=1
        else echo "PASS: rc $action $fault continues and preserves first failure"; fi
    done
done
fault=multiple; status=0
( __rc_jails boot ) > "$workdir/multiple.log" 2>&1 || status=$?
if [ "$status" != 43 ]; then
    echo 'FAIL: rc boot replaced the first failure with a later error'; failed=1
else echo 'PASS: rc boot retains the first of distinct startup failures'; fi
# Reserve a unique UUID-shaped log without overwriting anyone else's file.
background=$(printf '%s\n' "$workdir" | cksum | awk '{printf "00000000-0000-0000-0000-%012x", $1}')
candidate_log="/var/tmp/$background"
( set -C; : > "$candidate_log" ) || exit 1
background_log="$candidate_log"
mkdir "$workdir/$background"
printf 'host_hostuuid=%s\nboot=on\nhostid=%s\npriority=99\n' \
    "$background" "$hostid" > "$workdir/$background/config"
cat () {
    if [ "$fault" = background-cat-failure ] && [ "$1" = "$background_log" ]; then
        echo 'injected background log-read failure' >&2; return 45
    fi
    command cat "$@"
}
for fault in background-return background-exit background-success background-cat-failure; do
    visible="background start failed for $background; see $background_log"
    retained='injected background failure'
    case "$fault" in background-success|background-cat-failure)
        retained='completed background start'; visible="$retained" ;;
    esac
    [ "$fault" != background-cat-failure ] || visible='injected background log-read failure'
    rm -f "$workdir/background-release" "$workdir/background-entered" \
        "$workdir/background-finished" "$workdir/background-status"
    ( status=0; __rc_jails boot || status=$?
      echo "$status" > "$workdir/background-status"
    ) > "$workdir/$fault.log" 2>&1 &
    driver=$!; attempts=0
    while [ ! -f "$workdir/background-status" ] && [ "$attempts" -lt 100 ]; do
        sleep 0.1; attempts=$((attempts + 1))
    done
    nonblocking=no
    if [ -f "$workdir/background-entered" ] &&
        [ -f "$workdir/background-status" ] && [ ! -f "$workdir/background-finished" ]; then
        nonblocking=yes
    fi
    : > "$workdir/background-release"
    wait "$driver"
    attempts=0
    while ! grep -F "$visible" "$workdir/$fault.log" >/dev/null && [ "$attempts" -lt 30 ]; do
        sleep 0.1; attempts=$((attempts + 1))
    done
    if [ "$nonblocking" != yes ] || [ "$(cat "$workdir/background-status")" != 0 ] ||
        ! grep -q "$retained" "$background_log" ||
        ! grep -F "$visible" "$workdir/$fault.log" >/dev/null; then
        echo "FAIL: rc $fault nonblocking=$nonblocking," \
            "status=$(cat "$workdir/background-status"); missing output/diagnostic"
        failed=1
    else echo "PASS: rc $fault returns without waiting, retains output and reports the correct outcome"; fi
    case "$fault" in background-success|background-cat-failure)
        if grep -q 'background start failed for' "$workdir/$fault.log"; then
            echo 'FAIL: successful background start was mislabeled as failed'; failed=1
        fi ;;
    esac
done
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
