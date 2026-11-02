#!/bin/sh
# Unsupported paths must not stage another repository or start host mutations.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-git
. ./lib/ioc-upgrade
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-unsupported.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
__get_default_prop () { echo https://example.invalid/owned; }
__get_jail_prop () { echo 15.1-RELEASE; }
for command in git zfs mount umount chroot fetch; do
    eval "$command () { printf '%s\n' '$command' \"\$*\" >> \"\$trace\"; return 99; }"
done
failed=0
for mode in push update-ports fetch-ports; do
    state="$workdir/$mode"; iocroot="$state/iocell"
    mkdir -p "$iocroot/releases/15.1-RELEASE/root/etc"
    trace="$state/actions"; : > "$trace"; status=0
    (
        cd "$state"
        case "$mode" in
            push) __push owner/repo ;;
            update-ports) __update -p 15.1-RELEASE ;;
            fetch-ports) iocset_release=15.1-RELEASE; pool=tank
                ftpfiles=base.txz; ftplocaldir="$state"; __fetch_release -p ;;
        esac
    ) > "$state/result.log" 2>&1 || status=$?
    if [ "$status" = 0 ] || [ -s "$trace" ] || [ ! -s "$state/result.log" ]; then
        echo "FAIL: unsupported $mode succeeded or reached host/repository operations"; failed=1
    else echo "PASS: unsupported $mode refuses before host/repository operations"; fi
done
exit "$failed"
