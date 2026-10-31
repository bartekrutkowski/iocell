#!/bin/sh
# Exercise the real property setter with mocked ZFS and configuration storage.
# The legacy setter permits unset optional properties, so do not enable -u.
set -e

cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-zfs

workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-template.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM
pool=tank
original_uuid=11111111-1111-1111-1111-111111111111
tag=template-fixture
source_dataset="${pool}/iocell/templates/${tag}"
target_dataset="${pool}/iocell/jails/${original_uuid}"
dependent_dataset="${pool}/iocell/jails/22222222-2222-2222-2222-222222222222"

__validate_pname () {
    echo custom
}

__get_jail_prop () {
    case "$1" in
        tag)
            if [ -z "$3" ] ; then
                echo 'missing tag dataset' >> "${trace}"
                return 1
            fi

            echo "${tag}"
            ;;
        host_hostuuid) echo "${stored_uuid}" ;;
        type) [ "${source_mode:-template}" != jail ] && echo template || echo basejail ;;
        mountpoint) echo "${iocroot}/${3#${pool}/iocell/}" ;;
        *) return 1 ;;
    esac
}

__is_running () {
    if [ "$1" = "${running_name}" ] ; then
        echo 1
    fi
}

__ucl_set () {
    [ "${type_failure:-no}" != yes ] || [ "$2" != type ] || return 6
    printf '%s %s %s\n' "$1" "$2" "$3" >> "${writes}"
}

__link_tag () {
    printf 'link %s %s\n' "$1" "$2" >> "${trace}"
    [ "${link_failure:-no}" != yes ] || return 6
}

__check_basejail () {
    printf 'check %s %s\n' "$1" "$2" >> "${trace}"
    [ "${check_failure:-no}" != yes ] || {
        echo 'injected basejail migration failure' >&2; return 42;
    }
}

__umount_basejail () {
    printf 'umount %s %s\n' "$1" "$2" >> "${trace}"
}

zfs () {
    case "$1" in
        get)
            case " $* " in
                *' creation '*'/data '*)
                    [ "${data_mode}" != none ]
                    ;;
                *' jailed '*) cat "${data_state}" ;;
                *' origin '*)
                    [ "${query_failure}" != yes ] || return 9
                    [ "${origin_failure}" != yes ] || return 8
                    printf '%s\t-\n' "${source_dataset}/root"
                    if [ "${dependent}" = yes ] ; then
                        printf '%s\t%s\n' "${dependent_dataset}/root" \
                            "${source_dataset}/root@saved"
                    fi
                    ;;
                *) return 1 ;;
            esac
            ;;
        set)
            printf '%s %s\n' "$2" "$3" >> "${trace}"
            printf '%s\n' "${2#jailed=}" > "${data_state}"
            ;;
        rename)
            printf 'rename %s %s\n' "$3" "$4" >> "${trace}"

            if [ "${rename_failure}" = yes ] ; then
                return 7
            fi

            mv "${iocroot}/${3#${pool}/iocell/}" \
                "${iocroot}/${4#${pool}/iocell/}"
            ;;
        *) return 1 ;;
    esac
}

run_case () {
    local _label _want_status _status

    _label="$1"
    _want_status="$2"
    iocroot="${workdir}/${_label}"
    trace="${workdir}/${_label}.trace"
    writes="${workdir}/${_label}.writes"
    data_state="${workdir}/${_label}.jailed"
    mkdir -p "${iocroot}/templates/${tag}" "${iocroot}/jails"
    : > "${trace}"
    : > "${writes}"
    stored_uuid="${original_uuid}"
    data_mode=none
    dependent=no
    running_name=''
    rename_failure=no
    query_failure=no
    origin_failure=no
    type_failure=no; link_failure=no; check_failure=no; source_mode=template
    source_dataset="${pool}/iocell/templates/${tag}"

    case "${_label}" in
        delegated-on) data_mode=on ;;
        delegated-off) data_mode=off ;;
        invalid-uuid) stored_uuid=not-a-uuid ;;
        missing-uuid) stored_uuid='' ;;
        unsafe-uuid) stored_uuid='../other' ;;
        rename-failure) rename_failure=yes; data_mode=on ;;
        dependent-clone) dependent=yes ;;
        running-uuid) running_name="${original_uuid}" ;;
        running-tag) running_name="${tag}" ;;
        query-status-9) query_failure=yes ;;
        origin-failure) origin_failure=yes ;;
        type-failure) type_failure=yes; data_mode=on ;;
        link-failure) link_failure=yes; data_mode=on ;;
        check-failure) check_failure=yes ;;
        base-tag-collision)
            source_mode=jail; data_mode=on
            source_dataset="${target_dataset}"
            mkdir -p "${iocroot}/jails/${original_uuid}"
            ;;
    esac

    echo "${data_mode}" > "${data_state}"
    _status=0
    (
        __set_jail_prop istemplate=no "${tag}" "${source_dataset}"
    ) > "${workdir}/${_label}.log" 2>&1 || _status=$?

    if [ "${_status}" -ne "${_want_status}" ] ; then
        echo "FAIL: ${_label}: status ${_status}, want ${_want_status}" >&2
        cat "${workdir}/${_label}.log" >&2
        return 1
    fi

    if [ "${_want_status}" -eq 0 ] ; then
        [ -d "${iocroot}/jails/${original_uuid}" ] || return 1
        [ ! -d "${iocroot}/templates/${tag}" ] || return 1
        grep -Fx "link ${target_dataset} ${tag}" "${trace}" >/dev/null || \
            return 1
        grep -Fx "check ${original_uuid} ${target_dataset}" \
            "${trace}" >/dev/null || return 1
        grep -Fx "umount ${original_uuid} ${target_dataset}" \
            "${trace}" >/dev/null || return 1
        grep -F ' type basejail' "${writes}" >/dev/null || return 1
        grep -F ' istemplate no' "${writes}" >/dev/null || return 1
    elif [ "${_label}" = type-failure ] || [ "${_label}" = link-failure ] ; then
        [ -d "${iocroot}/jails/${original_uuid}" ] || return 1
        [ ! -d "${iocroot}/templates/${tag}" ] || return 1
        ! grep -q ' istemplate no' "${writes}" || return 1
        ! grep -Eq '^(check|umount) ' "${trace}" || return 1
    elif [ "${_label}" = check-failure ] ; then
        [ -d "${iocroot}/jails/${original_uuid}" ] || return 1
        ! grep -q ' istemplate no' "${writes}" || return 1
        ! grep -q '^umount ' "${trace}" || return 1
        grep -q 'injected basejail migration failure' \
            "${workdir}/${_label}.log" || return 1
    elif [ "${_label}" = base-tag-collision ] ; then
        [ -d "${iocroot}/templates/${tag}" ] || return 1
        [ -d "${iocroot}/jails/${original_uuid}" ] || return 1
        [ ! -s "${writes}" ] || return 1
        ! grep -Eq '^(jailed=|rename )' "${trace}" || {
            echo 'FAIL: basejail conversion touched the colliding template' >&2; return 1;
        }
    else
        [ -d "${iocroot}/templates/${tag}" ] || return 1
        [ ! -d "${iocroot}/jails/${original_uuid}" ] || return 1
        [ ! -s "${writes}" ] || return 1

        if grep -Eq '^(link|check|umount) ' "${trace}" ; then
            echo "FAIL: ${_label}: post-rename actions ran on failure" >&2
            return 1
        fi
    fi

    [ "$(cat "${data_state}")" = "${data_mode}" ] || return 1

    if grep -q '^missing tag dataset$' "${trace}" ; then
        echo "FAIL: ${_label}: tag lookup omitted its dataset" >&2
        return 1
    fi

    echo "PASS: ${_label}"
}

failed=0
for label in stored-uuid delegated-on delegated-off ; do
    run_case "${label}" 0 || { echo "FAIL: ${label}" >&2; failed=1; }
done
for label in invalid-uuid missing-uuid unsafe-uuid dependent-clone \
    running-uuid running-tag ; do
    run_case "${label}" 1 || { echo "FAIL: ${label}" >&2; failed=1; }
done
run_case rename-failure 7 || failed=1
run_case query-status-9 9 || failed=1
run_case origin-failure 8 || failed=1
run_case type-failure 6 || { echo 'FAIL: post-rename type failure was ignored'; failed=1; }
run_case link-failure 6 || { echo 'FAIL: post-rename alias failure was ignored'; failed=1; }
run_case base-tag-collision 1 || failed=1
run_case check-failure 42 || { echo 'FAIL: reverse conversion hid migration failure'; failed=1; }

# The CLI must not mask a failed conversion or apply later properties/jails.
source_dataset="${pool}/iocell/templates/${tag}"
. ./lib/ioc-cmd
. ./tests/cli-dispatch.sh
__export_props () {
    :
}

__find_jail () {
    echo "${source_dataset}"
}

__set_jail_prop () {
    printf '%s %s\n' "$1" "$2" >> "${trace}"
    return 7
}

trace="${workdir}/set-failure.trace"
: > "${trace}"
status=0
( ioc_test_dispatch set istemplate=no boot=on first second ) \
    > "${workdir}/set-failure.log" 2>&1 || status=$?
printf 'istemplate=no %s\n' "${tag}" > "${workdir}/set-failure.expected"

if [ "${status}" -eq 7 ] && \
    diff -u "${workdir}/set-failure.expected" "${trace}" ; then
    echo 'PASS: set-failure stops later properties and jails'
else
    echo 'FAIL: CLI masked a failed property change' >&2
    failed=1
fi
exit "${failed}"
