#!/bin/sh
# Read-only authorization checks; source after changing to the repository root.
ioc_test_error () {
    printf 'Native test refused: %s\n' "$*" >&2
    return 1
}

ioc_test_require_pool () {
    local _marker _root _mounted _selected
    [ "${IOC_TEST_DESTRUCTIVE:-}" = yes ] || {
        ioc_test_error 'set IOC_TEST_DESTRUCTIVE=yes on a disposable host'
        return 1
    }
    [ -n "${IOC_TEST_POOL:-}" ] || {
        ioc_test_error 'set IOC_TEST_POOL to the disposable activated pool'
        return 1
    }
    [ "$(uname -s)" = FreeBSD ] && [ "$(id -u)" = 0 ] || {
        ioc_test_error 'root on FreeBSD is required'
        return 1
    }
    _marker=$(zfs get -H -s local -o value org.freebsd.iocell:test \
        "$IOC_TEST_POOL") || {
        ioc_test_error "cannot read test marker on $IOC_TEST_POOL"
        return 1
    }
    [ "$_marker" = yes ] || {
        ioc_test_error "mark only a disposable pool: zfs set org.freebsd.iocell:test=yes $IOC_TEST_POOL"
        return 1
    }
    # Read the configured literal root without invoking iocell, whose normal
    # read commands can initialize/migrate filesystems before returning a value.
    _root=$(awk '/^iocroot=/ {
        value=substr($0,index($0,"=")+1)
        sub(/^"/,"",value); sub(/"$/,"",value); print value
    }' lib/ioc-globals)
    case "$_root" in
        /*) ;;
        *) ioc_test_error 'cannot determine the configured iocroot'; return 1 ;;
    esac
    [ "$_root" != / ] || { ioc_test_error 'iocroot must not be /'; return 1; }
    _mounted=$(df -P "$_root" | awk 'NR == 2 {print $1}')
    [ "$_mounted" = "$IOC_TEST_POOL/iocell" ] || {
        ioc_test_error "$_root is not mounted from $IOC_TEST_POOL/iocell"
        return 1
    }
    _selected=$(uclcmd get -qf "$_root/.default" pool) || {
        ioc_test_error 'cannot read the active-pool selector'
        return 1
    }
    [ "$_selected" = "$IOC_TEST_POOL" ] || {
        ioc_test_error "active pool $_selected differs from $IOC_TEST_POOL"
        return 1
    }
    IOC_TEST_ROOT="$_root"
    export IOC_TEST_ROOT
}

ioc_test_pool_name () {
    local _id
    _id=$(uuidgen) || return $?
    _id=$(printf '%s' "$_id" | tr -d '-')
    printf '%s%s\n' "$1" "$_id"
}
