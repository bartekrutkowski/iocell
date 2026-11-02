#!/bin/sh
# Native retained-data cases and a fresh real release preparation on scratch.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set IOC_TEST_RELEASE to the cached release}"
: "${IOC_TEST_DIST:?Set IOC_TEST_DIST to trusted base/lib32/src archives}"
workdir=$(mktemp -d /var/tmp/iocell-fetch-zfs.XXXXXX)
echo "Retained native fetch logs: $workdir"
. "${IOC_TEST_COMMON:-./lib/ioc-common}"
. ./lib/ioc-info
. ./lib/ioc-git
# An isolated dataset prefix keeps all OS bytes on the approved scratch pool.
# This exercises the actual backend/ZFS; CLI selection is tested separately.
ns="$IOC_TEST_POOL/fetch-$(uuidgen)"
zfs create -o mountpoint=none "$ns"
zfs create -o mountpoint="$workdir/tree" "$ns/iocell"
zfs create "$ns/iocell/releases"
zfs create "$ns/iocell/download"
pool="$ns"; iocroot="$workdir/tree"; compression=lz4
iocset_release="$IOC_TEST_RELEASE"; ftpfiles='base.txz lib32.txz src.txz'
ftplocaldir="$workdir/missing"; ftpdir=''; ftphost=ftp.freebsd.org
rel="$ns/iocell/releases/$IOC_TEST_RELEASE"
zfs create -p "$rel/root"
echo retained > "$iocroot/releases/$IOC_TEST_RELEASE/root/canary"
zfs snapshot "$rel/root@saved"
zfs clone "$rel/root@saved" "$ns/protected-clone"
zfs list -H -p -t all -r -o name,guid "$ns" > "$workdir/incomplete.before"
status=0
__fetch_release > "$workdir/incomplete.log" 2>&1 || status=$?
[ "$status" != 0 ]
[ "$(cat "$iocroot/releases/$IOC_TEST_RELEASE/root/canary")" = retained ]
zfs list -H -p -t all -r -o name,guid "$ns" > "$workdir/incomplete.after"
cmp "$workdir/incomplete.before" "$workdir/incomplete.after"
echo 'PASS: native incomplete fetch retains populated release, clone and GUIDs'
zfs rename "$rel" "$ns/retained-incomplete"
ftplocaldir="$IOC_TEST_DIST"
__fetch_release > "$workdir/fresh.log" 2>&1
root="$iocroot/releases/$IOC_TEST_RELEASE/root"
[ -s "$root/etcupdate/etcupdate-$IOC_TEST_RELEASE.tbz" ]
chroot "$root" /bin/freebsd-version -u > "$workdir/version"
grep -F "$IOC_TEST_RELEASE" "$workdir/version"
mount -p > "$workdir/mounts"
if grep -F "$root/dev" "$workdir/mounts"; then exit 1; fi
echo 'PASS: native fresh archives produce real userland and etcupdate baseline'

# The plugin caller must not delete partial data retained by a failed fetch.
__get_default_prop () { echo https://example.invalid; }
iocset_release=15.1-RELEASE-plugin
__fetch_release () {
    zfs create -p "$pool/iocell/releases/$iocset_release/root"
    echo partial > "$iocroot/releases/$iocset_release/root/canary"
    echo 'original release fetch diagnostic' >&2
    return 48
}
status=0
( set +u; __fetch_plugin owner/repo ) > "$workdir/plugin.log" 2>&1 || status=$?
[ "$status" = 48 ]
[ "$(cat "$iocroot/releases/$iocset_release/root/canary")" = partial ]
grep -F 'original release fetch diagnostic' "$workdir/plugin.log"
echo 'PASS: native plugin caller retains partial fetch data and primary error'

# A returned creation error must stop before Git can initialize the wrong tree.
iocset_release="$IOC_TEST_RELEASE"
mkdir -p "$workdir/create-failure/root"
__create_jail () { printf '<%s>\n' "$@" > "$workdir/create.args"; return 42; }
__get_jail_prop () { echo "$workdir/create-failure"; }
git () { echo touched >> "$workdir/git.actions"; exit 49; }
status=0
( set +u; __fetch_plugin owner/repo 'notes=two words' ) \
    > "$workdir/create-failure.log" 2>&1 || status=$?
[ "$status" = 42 ]
[ ! -e "$workdir/git.actions" ]
printf '<-g>\n<owner/repo>\n<notes=two words>\n' > "$workdir/create.expected"
cmp "$workdir/create.args" "$workdir/create.expected"
echo 'PASS: native plugin creation failure preserves payload and stops Git work'
