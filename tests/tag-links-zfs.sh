#!/bin/sh
# Real ZFS altroot/UCL effects through the production property setter.
# Select its pool/root explicitly: legacy CLI altroot bootstrap is a separate
# path and cannot select an altroot while the normal /iocell already exists.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
before=$(sha256 -q "$IOC_TEST_ROOT/.default")
workdir=$(mktemp -d /var/tmp/iocell-tags-zfs.XXXXXX)
p=$(ioc_test_pool_name ioctags)
echo "Retained tag logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -R "$workdir/altroot" -O mountpoint=none "$p" "$workdir/pool.vdev"
zpool set org.freebsd.iocell:test=yes "$p"
zfs create -o mountpoint=/iocell "$p/iocell"
zfs create "$p/iocell/jails"
root=$(zfs get -H -o value mountpoint "$p/iocell")
cat > "$workdir/set.sh" <<'HELPER'
#!/bin/sh
set +u
. ./lib/ioc-globals
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-zfs
pool="$IOC_TAG_POOL"; iocroot="$IOC_TAG_ROOT"
__set_jail_prop "$1" "$2" "$pool/iocell/jails/$2"
HELPER
backend_set () {
    env IOC_TAG_POOL="$p" IOC_TAG_ROOT="$root" sh "$workdir/set.sh" "tag=$1" "$2"
}
make_fixture () {
    id=$(uuidgen)
    zfs create "$p/iocell/jails/$id"
    zfs create "$p/iocell/jails/$id/root"
    mp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$id")
    printf 'host_hostuuid="%s"; tag="%s"; type="basejail"; istemplate="no";\n' \
        "$id" "$1" > "$mp/config"
    echo "$id"
}
old=$(make_fixture shared)
new=$(make_fixture candidate)
backend_set shared "$old"
backend_set candidate "$new"
oldmp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$old")
newmp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$new")
echo preserved > "$oldmp/root/marker"
guid=$(zfs get -H -o value guid "$p/iocell/jails/$old/root")
[ "$(readlink "$root/tags/shared")" = "../jails/$old" ]
backend_set shared "$new"
oldtag=$(uclcmd get -qf "$oldmp/config" tag)
[ "$oldtag" != shared ]
[ "$(readlink "$root/tags/$oldtag")" = "../jails/$old" ]
[ "$(readlink "$root/tags/shared")" = "../jails/$new" ]
[ "$(uclcmd get -qf "$newmp/config" tag)" = shared ]
[ "$(cat "$oldmp/root/marker")" = preserved ]
[ "$(zfs get -H -o value guid "$p/iocell/jails/$old/root")" = "$guid" ]
echo 'PASS: native altroot backend keeps both relative links and configurations consistent'

candidate=$(make_fixture another-candidate)
candidate_mp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$candidate")
mkdir "$workdir/writer-bin" "$workdir/link-bin"
cat > "$workdir/writer-bin/uclcmd" <<'WRAPPER'
#!/bin/sh
operation=$1; previous=''
for arg; do
    if [ "$operation" = set ] && [ "$previous" = -f ] && [ "$arg" = "$IOC_TAG_CONFIG" ]; then
        echo 'injected old-tag configuration failure' >&2; exit 42
    fi
    previous=$arg
done
exec /usr/local/bin/uclcmd "$@"
WRAPPER
cat > "$workdir/link-bin/ln" <<'WRAPPER'
#!/bin/sh
if [ "$1" = -sfn ]; then echo 'injected alias replacement failure' >&2; exit 42; fi
exec /bin/ln "$@"
WRAPPER
chmod +x "$workdir/writer-bin/uclcmd" "$workdir/link-bin/ln"
for fault in writer link; do
    status=0
    env PATH="$workdir/$fault-bin:$PATH" IOC_TAG_CONFIG="$newmp/config" \
        IOC_TAG_POOL="$p" IOC_TAG_ROOT="$root" sh "$workdir/set.sh" \
        tag=shared "$candidate" > "$workdir/$fault.log" 2>&1 || status=$?
    [ "$status" = 42 ]
    grep -q injected "$workdir/$fault.log"
    [ "$(uclcmd get -qf "$newmp/config" tag)" = shared ]
    [ "$(uclcmd get -qf "$candidate_mp/config" tag)" = another-candidate ]
    [ "$(readlink "$root/tags/shared")" = "../jails/$new" ]
    echo "PASS: native tag $fault failure preserves the existing owner's tag and alias"
done
mkdir "$workdir/unmanaged"
echo 'tag = "untouched";' > "$workdir/unmanaged/config"
cp "$workdir/unmanaged/config" "$workdir/unmanaged.before"
ln -s "$workdir/unmanaged" "$root/tags/foreign"
if backend_set foreign "$candidate" > "$workdir/foreign.log" 2>&1; then
    echo 'FAIL: foreign tag target accepted' >&2; exit 1
fi
grep -q 'outside the active jail namespace' "$workdir/foreign.log"
cmp "$workdir/unmanaged.before" "$workdir/unmanaged/config"
[ "$(uclcmd get -qf "$candidate_mp/config" tag)" = another-candidate ]
echo 'PASS: native foreign alias cannot redirect a configuration write'
backend_set another-candidate "$candidate"
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: altroot backend test preserves original defaults and activation'
zpool status -x
