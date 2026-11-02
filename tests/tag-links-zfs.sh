#!/bin/sh
# Real ZFS altroot/UCL effects through the production property setter.
# Select the backend explicitly; bootstrap-root-zfs.sh separately exercises
# public CLI selection while the normal /iocell directory also exists.
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
        target="$workdir/tree[ab]" ;;
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
cp "$newmp/config" "$workdir/owner-before"
aliases () {
    find "$root/tags" -type l -exec sh -c '
        for path; do printf "%s=%s\n" "$path" "$(readlink "$path")"; done
    ' sh {} + | sort
}
mkdir "$workdir/writer-bin" "$workdir/link-bin" "$workdir/move-bin" "$workdir/signal-bin"
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
cat > "$workdir/move-bin/mv" <<'WRAPPER'
#!/bin/sh
for target; do :; done
if [ "$target" = "$IOC_TAG_CONFIG" ] && [ ! -e "$IOC_TAG_MOVED" ]; then
    /bin/mv "$@" || exit $?
    touch "$IOC_TAG_MOVED"
    echo 'injected failure after config replacement' >&2; exit 42
fi
exec /bin/mv "$@"
WRAPPER
cat > "$workdir/signal-bin/uclcmd" <<'WRAPPER'
#!/bin/sh
previous=''
for arg; do
    if [ "$1" = set ] && [ "$previous" = -f ] && [ "$arg" = "$IOC_TAG_CONFIG" ]; then
        echo 'injected tag-update interruption' >&2
        kill -TERM "$PPID"
        exit 42
    fi
    previous=$arg
done
exec /usr/local/bin/uclcmd "$@"
WRAPPER
chmod +x "$workdir/writer-bin/uclcmd" "$workdir/link-bin/ln" \
    "$workdir/move-bin/mv" "$workdir/signal-bin/uclcmd"
for fault in writer link source-writer collision-source-writer after-write new-link signal dangling; do
    status=0; want=42; bin="$fault"; config="$newmp/config"; requested=shared; newlink=no
    case "$fault" in
        source-writer) bin=writer; config="$candidate_mp/config"; requested=unused-tag ;;
        collision-source-writer) bin=writer; config="$candidate_mp/config" ;;
        after-write) bin=move; config="$candidate_mp/config" ;;
        new-link) bin=link; requested=unused-link; newlink=yes ;;
        signal) config="$candidate_mp/config"; want=143 ;;
        dangling)
            bin=writer; config="$candidate_mp/config"; requested=stale-fault
            ln -s ../missing "$root/tags/$requested" ;;
    esac
    aliases > "$workdir/$fault.aliases-before"
    env PATH="$workdir/$bin-bin:$PATH" IOC_TAG_CONFIG="$config" \
        IOC_TAG_MOVED="$workdir/$fault.injected" IOC_TAG_NEWLINK_FAULT="$newlink" IOC_TAG_POOL="$p" IOC_TAG_ROOT="$root" \
        sh "$workdir/set.sh" "tag=$requested" "$candidate" \
        > "$workdir/$fault.log" 2>&1 || status=$?
    [ "$status" = "$want" ]
    grep -q injected "$workdir/$fault.log"
    cmp "$newmp/config" "$workdir/owner-before"
    cmp "$candidate_mp/config" "$workdir/candidate-before"
    aliases > "$workdir/$fault.aliases-after"
    cmp "$workdir/$fault.aliases-before" "$workdir/$fault.aliases-after"
    [ -z "$(find "$root/jails" -name '.iocell-tag.*' -print)" ]
    [ "$(readlink "$root/tags/shared")" = "$linkbase/$new" ]
    [ "$(readlink "$root/tags/another-candidate")" = "$linkbase/$candidate" ] || {
        echo "FAIL: native tag $fault removed the source's original alias" >&2; exit 1;
    }
    [ "$(cat "$candidate_mp/root/canary")" = preserved ]
    [ "$(zfs get -H -o value guid "$p/iocell/jails/$candidate/root")" = "$candidate_guid" ]
    echo "PASS: native tag $fault failure retains source aliases, config, data and GUID"
done
retry=$(make_fixture retry-candidate)
retry_mp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$retry")
backend_set retry-candidate "$retry"
status=0
env PATH="$workdir/writer-bin:$PATH" IOC_TAG_CONFIG="$retry_mp/config" \
    IOC_TAG_POOL="$p" IOC_TAG_ROOT="$root" sh "$workdir/set.sh" tag=shared "$retry" \
    > "$workdir/retry.log" 2>&1 || status=$?
[ "$status" = 42 ]
grep -q injected "$workdir/retry.log"
cmp "$newmp/config" "$workdir/owner-before"
[ "$(readlink "$root/tags/shared")" = "$linkbase/$new" ]
echo 'PASS: native failed retag does not block reassignment by another jail'
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
ln -s ../missing "$root/tags/stale"
backend_set stale "$candidate"
[ "$(readlink "$root/tags/stale")" = "$linkbase/$candidate" ]
[ "$(uclcmd get -qf "$candidate_mp/config" tag)" = stale ]
echo 'PASS: native tag assignment replaces a dangling alias'
backend_set another-candidate "$candidate"
[ "$(readlink "$root/tags/another-candidate")" = "$linkbase/$candidate" ]
backend_set 'new[1]*?' "$candidate"
[ "$(readlink "$root/tags/new[1]*?")" = "$linkbase/$candidate" ]
[ "$(uclcmd get -qf "$candidate_mp/config" tag)" = 'new[1]*?' ]
[ ! -L "$root/tags/another-candidate" ] && [ ! -L "$root/tags/unused-tag" ]
echo 'PASS: native successful retag keeps the literal new alias and removes old aliases'
# A plausible config below jails/ is not proof of a mounted dataset owner.
owned=$(make_fixture owned-candidate)
ownedmp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$owned")
backend_set owned-candidate "$owned"
loose=$(uuidgen); loosemp="$root/jails/$loose"
mkdir "$loosemp"
cp "$ownedmp/config" "$loosemp/config"
uclcmd set -u -f "$loosemp/config" -t string -- tag unowned-owner
ln -s "$loosemp" "$root/tags/unowned-owner"
cp "$loosemp/config" "$workdir/loose.before"
cp "$ownedmp/config" "$workdir/owned.before"
if backend_set unowned-owner "$owned" > "$workdir/unowned.log" 2>&1; then
    echo 'FAIL: unowned directory was retagged as a jail' >&2; exit 1
fi
cmp "$loosemp/config" "$workdir/loose.before"
cmp "$ownedmp/config" "$workdir/owned.before"
[ "$(readlink "$root/tags/unowned-owner")" = "$loosemp" ]
echo 'PASS: native tag collision refuses a live unowned directory without changing configs'

# A leftover host directory must not stand in for an unmounted source dataset.
unmounted=$(make_fixture unmounted-source)
unmounted_ds="$p/iocell/jails/$unmounted"
unmounted_mp=$(zfs get -H -o value mountpoint "$unmounted_ds")
backend_set unmounted-source "$unmounted"
cp "$unmounted_mp/config" "$workdir/unmounted.before"
zfs unmount "$unmounted_ds/root"; zfs unmount "$unmounted_ds"
mkdir -p "$unmounted_mp"
cp "$workdir/unmounted.before" "$unmounted_mp/config"
if backend_set unmounted-new "$unmounted" > "$workdir/unmounted.log" 2>&1; then exit 1; fi
cmp "$unmounted_mp/config" "$workdir/unmounted.before"
if backend_set unmounted-source "$owned" > "$workdir/unmounted-owner.log" 2>&1; then exit 1; fi
cmp "$ownedmp/config" "$workdir/owned.before"
cmp "$unmounted_mp/config" "$workdir/unmounted.before"
mv "$unmounted_mp/config" "$workdir/unmounted.host-shadow"
zfs mount "$unmounted_ds"; zfs mount "$unmounted_ds/root"
cmp "$unmounted_mp/config" "$workdir/unmounted.before"
echo 'PASS: native unmounted source refusal preserves host-shadow and dataset configs'

# A failed obsolete-alias operation may have taken effect before reporting error.
owner=$(make_fixture cleanup-shared); source=$(make_fixture cleanup-source)
owner_mp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$owner")
source_mp=$(zfs get -H -o value mountpoint "$p/iocell/jails/$source")
backend_set cleanup-shared "$owner"; backend_set cleanup-source "$source"
cp "$owner_mp/config" "$workdir/cleanup-owner.before"
cp "$source_mp/config" "$workdir/cleanup-source.before"
aliases > "$workdir/cleanup-aliases.before"
mkdir "$workdir/retire-bin"
cat > "$workdir/retire-bin/alias-op" <<'WRAPPER'
#!/bin/sh
tool=${0##*/}; source=$1
if [ "$tool" = rm ]; then for source; do :; done; fi
if [ "$source" = "$IOC_TAG_FAIL_ALIAS" ]; then
    "/bin/$tool" "$@" || exit $?
    echo 'injected failure after retiring obsolete alias' >&2
    exit 42
fi
exec "/bin/$tool" "$@"
WRAPPER
chmod +x "$workdir/retire-bin/alias-op"
ln -s alias-op "$workdir/retire-bin/rm"; ln -s alias-op "$workdir/retire-bin/mv"
status=0
env PATH="$workdir/retire-bin:$PATH" IOC_TAG_FAIL_ALIAS="$root/tags/cleanup-source" \
    IOC_TAG_POOL="$p" IOC_TAG_ROOT="$root" sh "$workdir/set.sh" \
    tag=cleanup-shared "$source" > "$workdir/cleanup-failure.log" 2>&1 || status=$?
[ "$status" != 0 ]
grep -q injected "$workdir/cleanup-failure.log"
cmp "$owner_mp/config" "$workdir/cleanup-owner.before"
cmp "$source_mp/config" "$workdir/cleanup-source.before"
aliases > "$workdir/cleanup-aliases.after"
cmp "$workdir/cleanup-aliases.before" "$workdir/cleanup-aliases.after"
[ -z "$(find "$root" -type d -name '.iocell-alias.*')" ]
echo 'PASS: native alias cleanup failure restores both configs and complete alias namespace'
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: tag backend test preserves original defaults and activation'
zpool status -x
