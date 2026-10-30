#!/bin/sh
# Opt-in FreeBSD template round-trip tests. Keep all filesystem fixtures.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set IOC_TEST_RELEASE to a fetched FreeBSD release}"

iocell () {
    sh ./iocell "$@"
}

workdir=$(mktemp -d /var/tmp/iocell-template.XXXXXX)
tag="toggle-test-$(date +%s)-$$"
iocell create "release=${IOC_TEST_RELEASE}" "tag=${tag}" vnet=off \
    ip4_addr=none ip6_addr=none \
    > "${workdir}/create.log" 2>&1
uuid=$(iocell get host_hostuuid "${tag}")
dataset="${IOC_TEST_POOL}/iocell/jails/${uuid}"
source="${IOC_TEST_POOL}/iocell/templates/${tag}"
parent=$(zfs get -H -o value mountpoint "${dataset}")
printf 'Retained template-test logs: %s\n' "${workdir}"
printf 'Retained original jail UUID: %s\n' "${uuid}"

collision_moved=0
cleanup () {
    if jls -j "ioc-${uuid}" jid >/dev/null 2>&1 ; then
        iocell stop "${uuid}" || :

        if jls -j "ioc-${uuid}" jid >/dev/null 2>&1 ; then
            jail -r "ioc-${uuid}"
        fi
    fi

    if [ "${collision_moved}" = 1 ] && \
        [ "$(zfs get -H -o value guid "${dataset}")" = \
            "${collision_guid}" ] ; then
        zfs rename "${dataset}" "${collision}"
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

printf 'round-trip content\n' > "${parent}/root/toggle-marker"
zfs snapshot "${dataset}/root@identity"
zfs create -o mountpoint=none -o jailed=on "${dataset}/data"
iocell set "jail_zfs_dataset=${dataset}/data" "${tag}"
root_guid=$(zfs get -H -o value guid "${dataset}/root")
data_guid=$(zfs get -H -o value guid "${dataset}/data")

template_prop () {
    uclcmd get -qf "$(zfs get -H -o value mountpoint "${source}")/config" \
        "$1"
}

for round in 1 2 ; do
    iocell set istemplate=yes "${uuid}"
    [ "$(template_prop host_hostuuid)" = "${uuid}" ]
    [ "$(template_prop type)" = template ]
    [ "$(template_prop istemplate)" = yes ]
    expected_jailed=on

    if [ "${round}" = 2 ] ; then
        zfs set jailed=off "${source}/data"
        expected_jailed=off
    fi

    iocell set istemplate=no "${tag}"
    zfs list -H "${dataset}" >/dev/null
    [ "$(iocell get host_hostuuid "${uuid}")" = "${uuid}" ]
    [ "$(iocell get type "${uuid}")" = basejail ]
    [ "$(iocell get istemplate "${uuid}")" = no ]
    [ "$(iocell get jail_zfs_dataset "${uuid}")" = "${dataset}/data" ]
    [ "$(zfs get -H -o value guid "${dataset}/root")" = "${root_guid}" ]
    [ "$(zfs get -H -o value guid "${dataset}/data")" = "${data_guid}" ]
    [ "$(zfs get -H -o value jailed "${dataset}/data")" = \
        "${expected_jailed}" ]
    [ "$(cat "${parent}/root/toggle-marker")" = 'round-trip content' ]
    [ "$(readlink "${IOC_TEST_ROOT}/tags/${tag}")" = "${parent}" ]
    zfs list -H -t snapshot "${dataset}/root@identity" >/dev/null
    if zfs list "${IOC_TEST_POOL}/iocell/jails/${tag}" >/dev/null 2>&1 ; then
        echo 'FAIL: jail dataset was renamed to its tag' >&2
        exit 1
    fi
    echo "PASS: round-trip ${round} preserves UUID, tag, data and snapshots"
done

iocell start "${uuid}" > "${workdir}/start.log" 2>&1 || {
    cat "${workdir}/start.log"
    exit 1
}
[ "$(iocell get state "${tag}")" = up ]
[ "$(iocell exec "${uuid}" /bin/sh -c 'echo identity-ok')" = identity-ok ]
iocell stop "${uuid}" > "${workdir}/stop.log" 2>&1
[ "$(iocell get state "${uuid}")" = down ]
echo 'PASS: returned jail starts, reports up, executes commands and stops'

# Forward conversion now preserves off as well as on. Explicitly prepare
# the delegated-on state whose restoration the following failures exercise.
zfs set jailed=on "${dataset}/data"
iocell set istemplate=yes "${uuid}"
iocell set host_hostuuid=not-a-uuid "${tag}"
if iocell set istemplate=no "${tag}" > "${workdir}/invalid.log" 2>&1 ; then
    echo 'FAIL: invalid stored UUID was accepted' >&2
    exit 1
fi
[ "$(template_prop type)" = template ]
[ "$(template_prop istemplate)" = yes ]
[ "$(zfs get -H -o value jailed "${source}/data")" = on ]
iocell set "host_hostuuid=${uuid}" "${tag}"
echo 'PASS: invalid UUID is rejected without changing template metadata'

# Template conversion may leave no tag symlink; preserve its actual state.
template_tag_link=$(readlink "${IOC_TEST_ROOT}/tags/${tag}" 2>/dev/null || :)

# Occupy the original UUID using a second, newly created empty fixture.
collision_uuid=$(iocell create -e "tag=${tag}-collision")
collision="${IOC_TEST_POOL}/iocell/jails/${collision_uuid}"
collision_guid=$(zfs get -H -o value guid "${collision}")
zfs rename "${collision}" "${dataset}"
collision_moved=1
if iocell set istemplate=no "${tag}" > "${workdir}/collision.log" 2>&1 ; then
    echo 'FAIL: occupied UUID destination was accepted' >&2
    exit 1
fi
[ "$(zfs get -H -o value guid "${dataset}")" = "${collision_guid}" ]
[ "$(template_prop type)" = template ]
[ "$(template_prop istemplate)" = yes ]
[ "$(zfs get -H -o value jailed "${source}/data")" = on ]
[ "$(readlink "${IOC_TEST_ROOT}/tags/${tag}" 2>/dev/null || :)" = \
    "${template_tag_link}" ]
zfs rename "${dataset}" "${collision}"
collision_moved=0
echo 'PASS: failed rename leaves template metadata and delegated state intact'

jail -c "name=ioc-${uuid}" "path=$(zfs get -H -o value mountpoint \
    "${source}/root")" persist ip4=disable ip6=disable
if iocell set istemplate=no "${tag}" > "${workdir}/running.log" 2>&1 ; then
    echo 'FAIL: running template was converted' >&2
    exit 1
fi
jail -r "ioc-${uuid}"
[ "$(template_prop type)" = template ]
echo 'PASS: running template is rejected before conversion'

zfs snapshot -r "${source}@dependent-test"
iocell clone "${tag}@dependent-test" "tag=${tag}-dependent" \
    > "${workdir}/clone.log" 2>&1
if iocell set istemplate=no "${tag}" > "${workdir}/dependent.log" 2>&1 ; then
    echo 'FAIL: template with a dependent clone was converted' >&2
    exit 1
fi
[ "$(template_prop type)" = template ]
[ "$(template_prop istemplate)" = yes ]
echo 'PASS: dependent clone prevents conversion; template and clone retained'
