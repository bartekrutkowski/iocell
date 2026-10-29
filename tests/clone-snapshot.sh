#!/bin/sh
# Exercise snapshot selection without requiring FreeBSD, root, or a ZFS pool.
set -eu

cd "$(dirname "$0")/.."
. ./lib/ioc-zfs

workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-clone.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM

pool=tank
uuid=11111111-1111-1111-1111-111111111111
source_uuid=22222222-2222-2222-2222-222222222222
source_dataset="tank/iocell/jails/${source_uuid}"
target_dataset="tank/iocell/jails/${uuid}"

__find_jail () {
    echo "${source_dataset}"
}

__check_name () {
    echo "${source_uuid}"
}

__configure_jail () {
    :
}

# Stop after the clone operations, before unrelated jail configuration.
__link_tag () {
    exit 0
}

# Record every ZFS call; unknown operations (including rename) fail the test.
zfs () {
    printf '%s\n' "$*" >> "${trace}"

    case "$1" in
        list)
            printf '%s\n' "${source_dataset}" "${source_dataset}/root"
            ;;
        snapshot)
            :
            ;;
        create)
            mkdir -p "${iocroot}/jails/${uuid}"
            ;;
        clone)
            :
            ;;
        *)
            echo "Unexpected ZFS operation: $*" >&2
            exit 1
            ;;
    esac
}

run_case () {
    local _label _argument _snapshot _create_snapshot

    _label="$1"
    _argument="$2"
    _snapshot="$3"
    _create_snapshot="$4"
    iocroot="${workdir}/${_label}"
    trace="${workdir}/${_label}.actual"

    (
        __clone_jail "${_argument}"
    )

    {
        echo "list -rH -o name ${source_dataset}"

        if [ "${_create_snapshot}" = "yes" ] ; then
            echo "snapshot ${source_dataset}/root@${_snapshot}"
        fi

        echo "create ${target_dataset}"
        echo "clone ${source_dataset}/root@${_snapshot} ${target_dataset}/root"
    } > "${workdir}/${_label}.expected"

    if diff -u "${workdir}/${_label}.expected" "${trace}" ; then
        echo "PASS: ${_label}"
    else
        echo "FAIL: ${_label}" >&2
        return 1
    fi
}

failed=0
run_case explicit-snapshot example@saved saved no || failed=1
run_case automatic-snapshot example "${uuid}" yes || failed=1
exit "${failed}"
