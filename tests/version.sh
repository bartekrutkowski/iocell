#!/bin/sh
# The public banner must match the upstream 2.2.0 release, not the 2017 banner.
set -eu
cd "$(dirname "$0")/.."
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-version.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
failed=0
for label in short long verbose-short verbose-long; do
    case "$label" in
        short) set -- version ;;
        long) set -- --version ;;
        verbose-short) set -- -v version ;;
        verbose-long) set -- -v --version ;;
    esac
    status=0
    "${TEST_SHELL:-sh}" ./iocell "$@" > "$workdir/$label.out" \
        2> "$workdir/$label.err" || status=$?
    printf 'iocell 2.2.0\n' > "$workdir/expected"
    if [ "$status" != 0 ] || ! cmp -s "$workdir/$label.out" "$workdir/expected"; then
        echo "FAIL: version $label is stale or failed"; failed=1
    else
        echo "PASS: version $label"
    fi
done
exit "$failed"
