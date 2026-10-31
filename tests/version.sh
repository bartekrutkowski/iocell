#!/bin/sh
# All public banner forms must match the independently declared project release.
set -eu
cd "$(dirname "$0")/.."
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-version.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
release=$(awk -F "'" '/^release = / {print $2}' doc/source/conf.py)
[ -n "$release" ]
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
    printf 'iocell %s\n' "$release" > "$workdir/expected"
    if [ "$status" != 0 ] || ! cmp -s "$workdir/$label.out" "$workdir/expected"; then
        echo "FAIL: version $label is stale or failed"; failed=1
    else
        echo "PASS: version $label"
    fi
done
exit "$failed"
