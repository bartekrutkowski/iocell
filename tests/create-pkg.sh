#!/bin/sh
# Test the package-creation mount lifecycle without mounting any filesystems.
set -eu

cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-configure
. ./lib/ioc-zfs

workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-create-pkg.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM
pool=tank
basedirs='bin usr/lib'

__get_jail_prop () {
    case "$1" in
        template) echo "${template}" ;;
        release) echo 15.1-RELEASE ;;
        *) return 1 ;;
    esac
}

mount () {
    local _type _source _target

    if [ "$1" = -p ] ; then
        cat "${mounts}"
        return
    fi

    _type=''

    while [ "$#" -gt 2 ] ; do
        case "$1" in
            -t) _type="$2"; shift 2 ;;
            -o) shift 2 ;;
            *) return 44 ;;
        esac
    done

    _source="$1"
    _target="$2"
    printf 'mount %s %s %s\n' "${_type}" "${_source}" "${_target}" \
        >> "${trace}"

    case "${_source}" in
        "${iocroot}/releases/15.1-RELEASE/root/"*|\
        "${iocroot}/templates/base/root/"*|\
        "${iocroot}/jails/short-id/_/"*|tmpfs|devfs) ;;
        *) return 44 ;;
    esac

    if [ "${_target}" = "${mount_failure}" ] ; then
        return 43
    fi

    printf '%s %s %s defaults 0 0\n' "${_source}" "${_target}" \
        "${_type}" >> "${mounts}"
}

umount () {
    printf 'umount %s\n' "$1" >> "${trace}"

    if [ "$1" = "${umount_failure}" ] ; then
        return 1
    fi

    awk -v target="$1" '
        { lines[NR] = $0; if ($2 == target) last = NR }
        END { for (i = 1; i <= NR; i++) if (i != last) print lines[i] }
    ' "${mounts}" > "${mounts}.new"
    mv "${mounts}.new" "${mounts}"
}

pkg () {
    echo pkg >> "${trace}"
    return "${pkg_status}"
}

run_case () {
    local _label _want_status _status

    _label="$1"
    _want_status="$2"
    iocroot="${workdir}/${_label}"
    root="${iocroot}/jails/short-id/root"
    mounts="${workdir}/${_label}.mounts"
    trace="${workdir}/${_label}.trace"
    pkglist="${workdir}/packages"
    mkdir -p "${root}/var" "${root}/etc" "${root}/usr/lib" \
        "${root}/bin" "${root}/dev" "${root}/tmp"
    printf 'pool/root %s zfs rw 0 0\nkeep /outside nullfs rw 0 0\n' \
        "${root}" > "${mounts}"
    : > "${trace}"
    echo example-package > "${pkglist}"
    mount_failure=''
    umount_failure=''
    pkg_status=0

    case "${_label}" in
        pkg-failure) pkg_status=42 ;;
        mount-failure) mount_failure="${root}/usr/lib" ;;
        legacy-mounts) mount_failure="${root}/bin" ;;
        tmpfs-failure) mount_failure="${root}/tmp" ;;
        devfs-failure) mount_failure="${root}/dev" ;;
        umount-failure) umount_failure="${root}/bin" ;;
        pkg-and-umount-failure)
            pkg_status=42
            umount_failure="${root}/bin"
            ;;
        preexisting-mount)
            printf 'existing %s/bin nullfs rw 0 0\n' "${root}" \
                >> "${mounts}"
            ;;
    esac

    cp "${mounts}" "${mounts}.initial"
    _status=0
    (
        if [ "${_label}" = legacy-mounts ] ; then
            __mount_basejail short-id 15.1-RELEASE
            _result=$?
            umount "${root}/tmp"
            umount "${root}/usr/lib"
            exit "${_result}"
        fi

        __create_jail_pkg short-id tank/iocell/jails/full-uuid
    ) > "${workdir}/${_label}.log" 2>&1 || _status=$?

    if [ "${_status}" -ne "${_want_status}" ] ; then
        echo "FAIL: ${_label}: status ${_status}, want ${_want_status}" >&2
        cat "${workdir}/${_label}.log" >&2
        return 1
    fi

    case "${_label}" in
        umount-failure|pkg-and-umount-failure) ;;
        *) diff -u "${mounts}.initial" "${mounts}" || return 1 ;;
    esac

    if [ "${_label}" = preexisting-mount ] ; then
        if [ -s "${trace}" ] ; then
            echo 'FAIL: preexisting mounts were changed' >&2
            return 1
        fi
    elif [ "${_label}" = mount-failure -o \
        "${_label}" = tmpfs-failure -o "${_label}" = devfs-failure -o \
        "${_label}" = legacy-mounts ] ; then
        if grep -q '^pkg$' "${trace}" ; then
            echo 'FAIL: pkg ran after a mount failure' >&2
            return 1
        fi
    else
        grep -q '^pkg$' "${trace}" || return 1
    fi

    echo "PASS: ${_label}"
}

failed=0
template=none
run_case release-mounts 0 || failed=1
run_case pkg-failure 42 || failed=1
run_case mount-failure 43 || failed=1
run_case tmpfs-failure 43 || failed=1
run_case devfs-failure 43 || failed=1
run_case umount-failure 1 || failed=1
run_case pkg-and-umount-failure 42 || failed=1
run_case preexisting-mount 1 || failed=1
run_case legacy-mounts 0 || failed=1
template=base
run_case template-mounts 0 || failed=1
exit "${failed}"
