#!/bin/sh
# Test package-list handling without root, networking, or package installation.
set -eu

cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-configure

workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-pkg.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM
trace="${workdir}/calls"
pkglist="${workdir}/packages"
jailroot=/fake/jail

pkg () {
    printf '%s\n' "$*" >> "${trace}"

    if [ "$#" -ne 5 -o "$2" != "${jailroot}" ] ; then
        return 43
    fi

    for _arg in "$@" ; do
        if [ "${_arg}" = broken-package ] ; then
            return 42
        fi
    done
}

run_case () {
    local _label _want_status _want_calls _status

    _label="$1"
    _want_status="$2"
    _want_calls="$3"
    : > "${trace}"
    _status=0
    ( __pkg_install "${jailroot}" ) > "${workdir}/output" 2>&1 || \
        _status=$?

    if [ "${_status}" -ne "${_want_status}" ] ; then
        echo "FAIL: ${_label}: status ${_status}, want ${_want_status}" >&2
        return 1
    fi

    if [ -n "${_want_calls}" ] ; then
        printf '%s\n' "${_want_calls}" > "${workdir}/expected"
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
printf 'broken-package\nworking-package\n' > "${pkglist}"
run_case first-failure 42 '-c /fake/jail install -qy broken-package' || \
    failed=1

printf 'working-package\nbroken-package\n' > "${pkglist}"
run_case later-failure 42 '-c /fake/jail install -qy working-package
-c /fake/jail install -qy broken-package' || failed=1

pkglist="${workdir}/package list"
jailroot='/fake/jail root'
printf '# package names\n\nworking-package' > "${pkglist}"
run_case comments-and-final-line 0 \
    '-c /fake/jail root install -qy working-package' || failed=1

: > "${pkglist}"
run_case empty-list 0 '' || failed=1
pkglist="${workdir}/missing"
run_case missing-list 1 '' || failed=1
pkglist="${workdir}"
run_case directory-list 1 '' || failed=1

exit "${failed}"
