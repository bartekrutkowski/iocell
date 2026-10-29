#!/bin/sh
# Opt-in integration test. Use only an activated, disposable iocell test pool.
# Filesystem fixtures and snapshots are retained; no existing jail is modified.
set -eu

cd "$(dirname "$0")/.."

if [ "$(uname -s)" != FreeBSD -o "$(id -u)" != 0 ] ; then
    echo 'This test requires root on FreeBSD with ZFS.' >&2
    exit 1
fi

: "${IOC_TEST_POOL:?Set IOC_TEST_POOL to an activated disposable test pool}"

iocell () {
    sh ./iocell "$@"
}

if [ "$(iocell get pool default)" != "${IOC_TEST_POOL}" ] ; then
    echo 'The activated pool does not match IOC_TEST_POOL.' >&2
    exit 1
fi

workdir=$(mktemp -d /tmp/iocell-rollback-zfs.XXXXXX)
running_jail=''
cleanup () {
    if [ -n "${running_jail}" ] ; then
        jail -r "${running_jail}"
    fi

    rm -rf "${workdir}"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

uuid=$(iocell create -e "tag=rollback-test-$(date +%s)-$$")
dataset="${IOC_TEST_POOL}/iocell/jails/${uuid}"
mountpoint=$(zfs get -H -o value mountpoint "${dataset}")
iocell set type=basejail "${uuid}"
zfs create "${dataset}/data"
printf 'root before\n' > "${mountpoint}/root/marker"
printf 'parent before\n' > "${mountpoint}/parent-marker"
printf 'data before\n' > "${mountpoint}/data/marker"

iocell snapshot -f "${uuid}@root-only"
printf 'root after\n' > "${mountpoint}/root/marker"
printf 'parent after\n' > "${mountpoint}/parent-marker"
printf 'data after\n' > "${mountpoint}/data/marker"
zfs snapshot "${dataset}/root@newer"
iocell rollback "${uuid}@root-only"
[ "$(cat "${mountpoint}/root/marker")" = 'root before' ]
[ "$(cat "${mountpoint}/parent-marker")" = 'parent after' ]
[ "$(cat "${mountpoint}/data/marker")" = 'data after' ]

if zfs list -H -t snapshot "${dataset}/root@newer" >/dev/null 2>&1 ; then
    echo 'FAIL: newer snapshot survived root-only rollback' >&2
    exit 1
fi

echo 'PASS: root-only rollback restores root, not parent or child data'

iocell snapshot -f -r "${uuid}@recursive"
printf 'root changed\n' > "${mountpoint}/root/marker"
printf 'parent changed\n' > "${mountpoint}/parent-marker"
printf 'data changed\n' > "${mountpoint}/data/marker"
iocell rollback "${uuid}@recursive"
[ "$(cat "${mountpoint}/root/marker")" = 'root before' ]
[ "$(cat "${mountpoint}/parent-marker")" = 'parent after' ]
[ "$(cat "${mountpoint}/data/marker")" = 'data after' ]
echo 'PASS: recursive rollback restores parent, root and child data'

expect_failure () {
    if iocell rollback "$1" > "${workdir}/failure.log" 2>&1 ; then
        echo "FAIL: rollback unexpectedly succeeded: $1" >&2
        exit 1
    fi
}

zfs create "${dataset}/new-child"
printf 'root unchanged\n' > "${mountpoint}/root/marker"
printf 'parent unchanged\n' > "${mountpoint}/parent-marker"
printf 'data unchanged\n' > "${mountpoint}/data/marker"
expect_failure "${uuid}@recursive"
[ "$(cat "${mountpoint}/root/marker")" = 'root unchanged' ]
[ "$(cat "${mountpoint}/parent-marker")" = 'parent unchanged' ]
[ "$(cat "${mountpoint}/data/marker")" = 'data unchanged' ]
zfs list -H "${dataset}/new-child" >/dev/null
echo 'PASS: missing child snapshot prevents every rollback; child survives'

expect_failure "${uuid}@missing"
expect_failure "${uuid}"
[ "$(cat "${mountpoint}/root/marker")" = 'root unchanged' ]
echo 'PASS: missing snapshots and missing snapshot names are rejected'

jail -c "name=ioc-${uuid}" "path=${mountpoint}/root" persist \
    ip4=disable ip6=disable
running_jail="ioc-${uuid}"
expect_failure "${uuid}@root-only"
[ "$(cat "${mountpoint}/root/marker")" = 'root unchanged' ]
jail -r "${running_jail}"
running_jail=''
echo 'PASS: running jail is rejected without changing its root'

zfs snapshot "${dataset}/root@protected"
printf 'newer content\n' > "${mountpoint}/root/marker"
zfs snapshot "${dataset}/root@cloned"
zfs clone "${dataset}/root@cloned" "${dataset}/dependent"
expect_failure "${uuid}@protected"
[ "$(cat "${mountpoint}/root/marker")" = 'newer content' ]
zfs list -H "${dataset}/dependent" >/dev/null
zfs list -H -t snapshot "${dataset}/root@cloned" >/dev/null
echo 'PASS: ZFS failure is propagated without destroying dependent clones'
printf 'Retained integration fixture: %s\n' "${dataset}"
