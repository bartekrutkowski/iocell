#!/bin/sh
# Unit callers mirror the public entrypoint: preflight, then private dispatch.
ioc_test_dispatch () {
    __validate_cmd "$@" || return $?
    __parse_cmd "$@"
}
