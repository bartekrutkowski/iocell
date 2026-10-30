#!/bin/sh
# Opt-in real package installation; use an activated disposable FreeBSD pool.
# Retains new fixtures and logs, and never starts a jail intentionally.
set -eu

cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set IOC_TEST_RELEASE to a fetched FreeBSD release}"

iocell () {
    sh ./iocell "$@"
}

release_root=$(zfs get -H -o value mountpoint \
    "${IOC_TEST_POOL}/iocell/releases/${IOC_TEST_RELEASE}/root")
[ -x "${release_root}/bin/sh" ]
[ -f "${release_root}/etcupdate/etcupdate-${IOC_TEST_RELEASE}.tbz" ]

workdir=$(mktemp -d /var/tmp/iocell-create-pkg.XXXXXX)
tag="pkg-test-$(date +%s)-$$"
abi=$(pkg config ABI)
osversion=$(sysctl -n kern.osreldate)
printf 'Retained package-test logs: %s\n' "${workdir}"
printf 'pkgconf\n' > "${workdir}/good-packages"
printf 'iocell-nonexistent-package-987654321\npkgconf\n' \
    > "${workdir}/bad packages"
: > "${workdir}/empty packages"

assert_no_mounts () {
    if mount -p | awk -v root="$1" '
        $3 != "zfs" && ($2 == root || index($2, root "/") == 1) { found = 1 }
        END { exit !found }
    ' ; then
        echo "FAIL: package mounts remain below $1" >&2
        exit 1
    fi
}

create () {
    iocell create "release=${IOC_TEST_RELEASE}" vnet=off "$@"
}

ln -s "$(pwd)/lib" "${workdir}/lib"
ln -s "$(pwd)/iocell" "${workdir}/iocell"
(
    cd "${workdir}"
    create "tag=${tag}-ok" pkglist=good-packages
) > "${workdir}/success.log" 2>&1 || {
        cat "${workdir}/success.log"
        exit 1
    }
uuid=$(iocell get host_hostuuid "${tag}-ok")
parent=$(zfs get -H -o value mountpoint \
    "${IOC_TEST_POOL}/iocell/jails/${uuid}")
[ -x "${parent}/root/usr/local/bin/pkgconf" ]
pkg -r "${parent}/root" -o "ABI=${abi}" -o "OSVERSION=${osversion}" \
    info -e pkgconf
assert_no_mounts "${parent}/root"
echo 'PASS: relative package list installs a real package; mounts cleaned'

# A deliberately absent source forces a real partial nullfs mount failure.
mkdir "${parent}/root/iocell-package-test-missing"
if (
    . ./lib/ioc-common
    . ./lib/ioc-info
    . ./lib/ioc-configure
    . ./lib/ioc-zfs
    pool="${IOC_TEST_POOL}"
    iocroot="${parent%/jails/*}"
    basedirs='bin iocell-package-test-missing'
    pkglist="${workdir}/good-packages"
    __create_jail_pkg "${parent##*/}" \
        "${IOC_TEST_POOL}/iocell/jails/${uuid}"
) > "${workdir}/mount-failure.log" 2>&1 ; then
    echo 'FAIL: missing nullfs source was accepted' >&2
    exit 1
fi
assert_no_mounts "${parent}/root"
if grep -q 'Installing extra packages' "${workdir}/mount-failure.log" ; then
    echo 'FAIL: packages ran after a partial mount failure' >&2
    exit 1
fi
echo 'PASS: real partial mount failure stops installation and cleans mounts'

if create "tag=${tag}-failed" "pkglist=${workdir}/bad packages" count=2 \
    start=1 > "${workdir}/failure.log" 2>&1 ; then
    echo 'FAIL: failed package installation reported success' >&2
    exit 1
fi
uuid=$(iocell get host_hostuuid "${tag}-failed_1")
parent=$(zfs get -H -o value mountpoint \
    "${IOC_TEST_POOL}/iocell/jails/${uuid}")
[ ! -e "${parent}/root/usr/local/bin/pkgconf" ]
assert_no_mounts "${parent}/root"
if jls -j "ioc-${uuid}" jid >/dev/null 2>&1 ; then
    jail -r "ioc-${uuid}"
    echo 'FAIL: failed jail was started' >&2
    exit 1
fi
if grep -q 'Successfully created:' "${workdir}/failure.log" ; then
    echo 'FAIL: failure printed a success message' >&2
    exit 1
fi
if iocell get host_hostuuid "${tag}-failed_2" >/dev/null 2>&1 ; then
    echo 'FAIL: count continued after a failed creation' >&2
    exit 1
fi
echo 'PASS: failed install stops count, skips later packages/start and cleans'

if create "tag=${tag}-missing" "pkglist=${workdir}/missing" \
    > "${workdir}/missing.log" 2>&1 ; then
    echo 'FAIL: missing package list was accepted' >&2
    exit 1
fi
if iocell get host_hostuuid "${tag}-missing" >/dev/null 2>&1 ; then
    echo 'FAIL: missing list created a jail' >&2
    exit 1
fi
echo 'PASS: missing package list is rejected before creating a jail'

create "tag=${tag}-empty" "pkglist=${workdir}/empty packages" \
    > "${workdir}/empty.log" 2>&1
uuid=$(iocell get host_hostuuid "${tag}-empty")
parent=$(zfs get -H -o value mountpoint \
    "${IOC_TEST_POOL}/iocell/jails/${uuid}")
assert_no_mounts "${parent}/root"
echo 'PASS: empty package list succeeds without leaving mounts'

# Exercise existing template creation rather than removing template support.
create "tag=${tag}-base" > "${workdir}/template-source.log" 2>&1
iocell set istemplate=yes "${tag}-base" \
    >> "${workdir}/template-source.log" 2>&1
create "tag=${tag}-overlay" "template=${tag}-base" \
    "pkglist=${workdir}/good-packages" > "${workdir}/template.log" 2>&1 || {
        cat "${workdir}/template.log"
        exit 1
    }
uuid=$(iocell get host_hostuuid "${tag}-overlay")
parent=$(zfs get -H -o value mountpoint \
    "${IOC_TEST_POOL}/iocell/jails/${uuid}")
[ -x "${parent}/root/usr/local/bin/pkgconf" ]
pkg -r "${parent}/_" -o "ABI=${abi}" -o "OSVERSION=${osversion}" \
    info -e pkgconf
assert_no_mounts "${parent}/root"
template_root=$(zfs get -H -o value mountpoint \
    "${IOC_TEST_POOL}/iocell/templates/${tag}-base")
[ ! -e "${template_root}/root/var/db/pkg/local.sqlite" ]
echo 'PASS: template packages use writable overlays and leave template intact'
