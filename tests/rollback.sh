#!/bin/sh
# Test rollback target selection and failure handling without a ZFS pool.
set -eu

cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-snapshot

workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-rollback.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM

dataset=tank/iocell/jails/11111111-1111-1111-1111-111111111111

__find_jail () {
    if [ "${find_failure}" = yes ] ; then
        echo 'injected jail lookup failure' >&2
        return 6
    fi
    echo "${dataset}"
}

__check_name () {
    echo 11111111-1111-1111-1111-111111111111
}

__is_running () {
    if [ "${running}" = yes ] ; then
        echo 1
    fi
}

zfs () {
    printf '%s\n' "$*" >> "${operations}"
    case "$1" in
        list)
            if [ "${list_failure}" = yes ] ; then
                return 7
            fi

            case " $* " in
                *' snapshot '*)
                    if [ "${list_failure}" = snapshots ] ; then
                        return 9
                    fi

                    printf '%s\n' "${snapshots}"
                    ;;
                *) printf '%s\n' "${filesystems}" ;;
            esac
            ;;
        rollback)
            printf '%s\n' "$*" >> "${trace}"

            if [ "${rollback_failure}" = yes ] ; then
                return 8
            fi
            ;;
        *)
            echo "Unexpected ZFS operation: $*" >&2
            exit 1
            ;;
    esac
}

run_case () {
    local _label _argument _expected_status _expected_calls _status

    _label="$1"
    _argument="$2"
    _expected_status="$3"
    _expected_calls="$4"
    trace="${workdir}/${_label}.actual"
    operations="${workdir}/${_label}.operations"
    : > "${trace}"; : > "${operations}"
    _status=0
    ( __rollback "${_argument}" ) > "${workdir}/${_label}.log" 2>&1 || \
        _status=$?

    if [ "${_status}" -ne "${_expected_status}" ] ; then
        echo "FAIL: ${_label}: status ${_status}, want ${_expected_status}"
        return 1
    fi

    if [ "${_label}" = lookup-failure ] ; then
        [ ! -s "${operations}" ] || return 1
        grep -q 'injected jail lookup failure' "${workdir}/${_label}.log" || return 1
    fi
    if [ -n "${_expected_calls}" ] ; then
        printf '%s\n' "${_expected_calls}" > "${workdir}/expected"
    else
        : > "${workdir}/expected"
    fi

    if diff -u "${workdir}/expected" "${trace}" ; then
        echo "PASS: ${_label}"
    else
        echo "FAIL: ${_label}" >&2
        return 1
    fi
}

failed=0
find_failure=no
running=no
list_failure=no
rollback_failure=no
filesystems="${dataset}
${dataset}/root
${dataset}/data"
snapshots="${dataset}/root@saved
${dataset}/data@unrelated"

run_case root-only example@saved 0 \
    "rollback -r ${dataset}/root@saved" || failed=1

snapshots="${dataset}@saved
${dataset}/root@saved
${dataset}/data@saved"
recursive_calls="rollback -r ${dataset}@saved
rollback -r ${dataset}/root@saved
rollback -r ${dataset}/data@saved"
run_case recursive example@saved 0 "${recursive_calls}" || failed=1

snapshots="${dataset}@saved
${dataset}/root@saved"
run_case missing-child example@saved 1 '' || failed=1

snapshots="${dataset}/root@saved-other
${dataset}/data@saved"
run_case missing-root example@saved 1 '' || failed=1
run_case missing-name example 1 '' || failed=1
run_case empty-jail-name @saved 1 '' || failed=1
find_failure=yes
run_case lookup-failure example@saved 6 '' || failed=1
find_failure=no

snapshots="${dataset}/root@saved"
running=yes
run_case running-jail example@saved 1 '' || failed=1
running=no

list_failure=yes
run_case list-failure example@saved 7 '' || failed=1
list_failure=snapshots
run_case snapshot-list-failure example@saved 9 '' || failed=1
list_failure=no

snapshots="${dataset}@saved
${dataset}/root@saved
${dataset}/data@saved"
rollback_failure=yes
run_case rollback-failure example@saved 8 \
    "rollback -r ${dataset}@saved" || failed=1

exit "${failed}"
