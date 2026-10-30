#!/bin/sh
# A receiving account may use csh: it must parse the outer SSH command.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-zfs
if ! command -v csh >/dev/null; then
    echo 'SKIP: csh parser unavailable'; exit 0
fi
ssh () {
    shift
    command csh -n -c "$*"
}
if ! __send_receive destination root@receiver 1 </dev/null; then
    echo 'FAIL: buffered SSH receiver command is not accepted by csh' >&2
    exit 1
fi
echo 'PASS: buffered SSH receiver command parses under csh'
