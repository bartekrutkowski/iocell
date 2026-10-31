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
case "${IOC_TAG_ALTROOT:-yes}" in
    yes)
        zpool create -R "$workdir/altroot" -O mountpoint=none "$p" "$workdir/pool.vdev"
        target=/iocell ;;
    no)
        zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
        target="$workdir/tree" ;;
    *) ioc_test_error 'IOC_TAG_ALTROOT must be yes or no'; exit 1 ;;
esac
zfs create -o mountpoint="$target" "$p/iocell"
zfs create "$p/iocell/jails"
root=$(zfs get -H -o value mountpoint "$p/iocell")
linkbase="$root/jails"
[ "${IOC_TAG_ALTROOT:-yes}" != yes ] || linkbase=../jails
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
[ "$(readlink "$root/tags/shared")" = "$linkbase/$old" ]
backend_set shared "$new"
oldtag=$(uclcmd get -qf "$oldmp/config" tag)
[ "$oldtag" != shared ]
[ "$(readlink "$root/tags/$oldtag")" = "$linkbase/$old" ]
[ "$(readlink "$root/tags/shared")" = "$linkbase/$new" ]
[ ! -L "$root/tags/candidate" ]
[ "$(uclcmd get -qf "$newmp/config" tag)" = shared ]
[ "$(cat "$oldmp/root/marker")" = preserved ]
[ "$(zfs get -H -o value guid "$p/iocell/jails/$old/root")" = "$guid" ]
echo "PASS: native tag backend keeps both owners consistent (altroot=${IOC_TAG_ALTROOT:-yes})"

candidate=$(make_fixture another-candidate)
candidate_mp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$candidate")
backend_set another-candidate "$candidate"
cp "$candidate_mp/config" "$workdir/candidate-before"
candidate_guid=$(zfs get -H -o value guid "$p/iocell/jails/$candidate/root")
echo preserved > "$candidate_mp/root/canary"
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
if [ "$1" = -sfn ] || { [ "${IOC_TAG_NEWLINK_FAULT:-no}" = yes ] && [ "$1" = -s ]; }; then
    echo 'injected alias replacement failure' >&2; exit 42
fi
exec /bin/ln "$@"
WRAPPER
chmod +x "$workdir/writer-bin/uclcmd" "$workdir/link-bin/ln"
for fault in writer link source-writer new-link; do
    status=0; bin="$fault"; config="$newmp/config"; requested=shared; newlink=no
    case "$fault" in
        source-writer) bin=writer; config="$candidate_mp/config"; requested=unused-tag ;;
        new-link) bin=link; requested=unused-link; newlink=yes ;;
    esac
    env PATH="$workdir/$bin-bin:$PATH" IOC_TAG_CONFIG="$config" \
        IOC_TAG_NEWLINK_FAULT="$newlink" IOC_TAG_POOL="$p" IOC_TAG_ROOT="$root" \
        sh "$workdir/set.sh" "tag=$requested" "$candidate" \
        > "$workdir/$fault.log" 2>&1 || status=$?
    [ "$status" = 42 ]
    grep -q injected "$workdir/$fault.log"
    [ "$(uclcmd get -qf "$newmp/config" tag)" = shared ]
    cmp "$candidate_mp/config" "$workdir/candidate-before"
    [ "$(readlink "$root/tags/shared")" = "$linkbase/$new" ]
    [ "$(readlink "$root/tags/another-candidate")" = "$linkbase/$candidate" ] || {
        echo "FAIL: native tag $fault removed the source's original alias" >&2; exit 1;
    }
    [ "$(cat "$candidate_mp/root/canary")" = preserved ]
    [ "$(zfs get -H -o value guid "$p/iocell/jails/$candidate/root")" = "$candidate_guid" ]
    echo "PASS: native tag $fault failure retains source aliases, config, data and GUID"
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
cmp "$candidate_mp/config" "$workdir/candidate-before"
[ "$(readlink "$root/tags/another-candidate")" = "$linkbase/$candidate" ]
echo 'PASS: native foreign alias rejection preserves both configurations and source alias'
backend_set another-candidate "$candidate"
[ "$(readlink "$root/tags/another-candidate")" = "$linkbase/$candidate" ]
backend_set 'new[1]*?' "$candidate"
[ "$(readlink "$root/tags/new[1]*?")" = "$linkbase/$candidate" ]
[ "$(uclcmd get -qf "$candidate_mp/config" tag)" = 'new[1]*?' ]
[ ! -L "$root/tags/another-candidate" ] && [ ! -L "$root/tags/unused-tag" ]
echo 'PASS: native successful retag keeps the literal new alias and removes old aliases'
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: tag backend test preserves original defaults and activation'
zpool status -x
