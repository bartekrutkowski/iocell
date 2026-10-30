#!/bin/sh
# Destructive, opt-in native safety checks using only new file-backed pools.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname -s)" = FreeBSD ] && [ "$(id -u)" = 0 ] || exit 1
: "${IOC_TEST_POOL:?Set IOC_TEST_POOL to the activated disposable test pool}"
iocell () {
    env PATH="$PATH" IOC_SAFETY_FAULT="${IOC_SAFETY_FAULT:-}" \
        sh ./iocell "$@"
}
original=$(iocell get pool default)
[ "$original" = "$IOC_TEST_POOL" ]
[ "$(jls -h jid | wc -l | tr -d ' ')" = 1 ] || {
    echo 'Stop all jails before this test.' >&2; exit 1;
}
workdir=$(mktemp -d /var/tmp/iocell-safety.XXXXXX)
src="iocs$$"; dst="iocd$$"
activated=0; config_saved=0; config_existed=0
cleanup () {
    status=$?
    trap - EXIT
    unset IOC_SAFETY_FAULT
    if [ "$config_saved" = 1 ]; then
        if [ "$config_existed" = 1 ]; then cp -p "$workdir/host-config" /config
        else rm -f /config; fi
    fi
    if [ "$activated" = 1 ]; then
        iocell activate "$original" > "$workdir/restore.log" 2>&1 || {
            echo "FAIL: restore activation; see $workdir/restore.log" >&2
            status=1
        }
    fi
    echo "Retained safety logs and file vdevs: $workdir"
    echo "Retained scratch pools: $src $dst"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
for p in "$src" "$dst"; do
    truncate -s 512M "$workdir/$p.vdev"
    zpool create -O mountpoint=none "$p" "$workdir/$p.vdev"
done
mkdir "$workdir/bin"
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
case "${IOC_SAFETY_FAULT:-}" in
    snapshot|receive|rename)
        [ "$1" != "$IOC_SAFETY_FAULT" ] || exit 42 ;;
    origin)
        case " $* " in *' origin '*) exit 42 ;; esac ;;
    send-after)
        if [ "$1" = send ]; then /sbin/zfs "$@" || exit $?; exit 42; fi ;;
    activate)
        if [ "$1" = set ] && [ "$2" = mountpoint=/iocell ] && \
            [ "$3" = "$IOC_SAFETY_DESTROOT" ]; then exit 42; fi ;;
    race)
        if [ "$1" = destroy ]; then
            /sbin/zfs clone "$IOC_SAFETY_TEMPLATE_ROOT" "$IOC_SAFETY_RACE_DEST"
        fi ;;
esac
exec /sbin/zfs "$@"
WRAPPER
chmod +x "$workdir/bin/zfs"
iocell activate "$src" > "$workdir/activate.log" 2>&1
activated=1
[ "$(iocell get pool default)" = "$src" ]
new_jail () {
    new_uuid=$(iocell create -e "tag=$1")
    iocell set type=basejail "tag=$1" "$new_uuid"
    new_ds="$src/iocell/jails/$new_uuid"
    new_mp=$(zfs get -H -o value mountpoint "$new_ds")
    echo preserved > "$new_mp/root/marker"
}
new_jail safety-discovery
u="$new_uuid"; ds="$new_ds"; mp="$new_mp"
cp "$mp/config" "$workdir/discovery-config"
zfs create "$ds/update-backup"
echo backup-data > "$mp/update-backup/canary"
iocell list > "$workdir/list.log" 2>&1
[ "$(iocell get tag "$u")" = safety-discovery ]
cmp "$mp/config" "$workdir/discovery-config"
[ "$(cat "$mp/update-backup/canary")" = backup-data ]
zfs destroy "$ds/update-backup"
echo 'PASS: read-only discovery ignores nested backup and preserves config/data'
guid_before=$(zfs get -H -o value guid "$ds/root")
if PATH="$workdir/bin:$PATH" IOC_SAFETY_FAULT=origin \
    iocell destroy -f "$u" > "$workdir/destroy-query.log" 2>&1; then
    echo 'FAIL: destroy ignored dependency-query failure' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$ds/root")" = "$guid_before" ]
cmp "$mp/config" "$workdir/discovery-config"
echo 'PASS: shared dependency-query failure also prevents jail destruction'
new_jail safety-legacy
legacy_guid=$(zfs get -H -o value guid "$new_ds/root")
zfs set org.freebsd.iocell:tag=safety-legacy \
    org.freebsd.iocell:type=basejail \
    "org.freebsd.iocell:host_hostuuid=$new_uuid" "$new_ds"
mv "$new_mp/config" "$workdir/legacy-before"
iocell list > "$workdir/legacy-migration.log" 2>&1
[ "$(iocell get tag "$new_uuid")" = safety-legacy ]
[ "$(iocell get host_hostuuid "$new_uuid")" = "$new_uuid" ]
[ "$(zfs get -H -o value guid "$new_ds/root")" = "$legacy_guid" ]
[ "$(cat "$new_mp/root/marker")" = preserved ]
echo 'PASS: genuine missing legacy config still migrates without changing jail data'

# The default generated tag is legal metadata but not a legal ZFS component.
bad=$(iocell create -e)
iocell set type=basejail "$bad"
bad_ds="$src/iocell/jails/$bad"
bad_mp=$(zfs get -H -o value mountpoint "$bad_ds")
cp "$bad_mp/config" "$workdir/bad-config"
if [ -e /config ]; then cp -p /config "$workdir/host-config"; config_existed=1
else printf 'safety_canary="unchanged";\n' > /config; fi
config_saved=1
cp /config "$workdir/host-sentinel"
if iocell set istemplate=yes "$bad" > "$workdir/bad-tag.log" 2>&1; then
    echo 'FAIL: generated unsafe template tag was accepted' >&2; exit 1
fi
cmp /config "$workdir/host-sentinel"
cmp "$bad_mp/config" "$workdir/bad-config"
echo 'PASS: invalid template tag changes neither jail metadata nor host /config'
for path in '' / none "$workdir/missing"; do
    if ( . ./lib/ioc-common; __ucl_set "$path" istemplate yes ) \
        > "$workdir/writer.log" 2>&1; then
        echo 'FAIL: invalid UCL mountpoint was accepted' >&2; exit 1
    fi
    cmp /config "$workdir/host-sentinel"
done
mkdir "$workdir/invalid-ucl"
printf '{ incomplete = "broken\n' > "$workdir/invalid-ucl/config"
cp "$workdir/invalid-ucl/config" "$workdir/invalid-ucl-before"
if ( . ./lib/ioc-common; __ucl_set "$workdir/invalid-ucl" istemplate yes ) \
    > "$workdir/writer-parser.log" 2>&1; then
    echo 'FAIL: UCL parser failure reported success' >&2; exit 1
fi
cmp "$workdir/invalid-ucl/config" "$workdir/invalid-ucl-before"
echo 'PASS: native UCL writer rejects invalid paths and preserves config on parser errors'

new_jail safety-template
u="$new_uuid"; ds="$new_ds"; mp="$new_mp"
zfs create -o mountpoint=none -o jailed=on "$ds/data"
iocell set "jail_zfs_dataset=$ds/data" "$u"
cp "$mp/config" "$workdir/rename-config"
alias_before=$(readlink /iocell/tags/safety-template)
if PATH="$workdir/bin:$PATH" IOC_SAFETY_FAULT=rename \
    iocell set istemplate=yes "$u" > "$workdir/rename.log" 2>&1; then
    echo 'FAIL: failed rename reported success' >&2; exit 1
fi
cmp "$mp/config" "$workdir/rename-config"
[ "$(zfs get -H -o value jailed "$ds/data")" = on ]
[ "$(readlink /iocell/tags/safety-template)" = "$alias_before" ]
echo 'PASS: failed rename preserves config, alias and delegated state'
root_guid=$(zfs get -H -o value guid "$ds/root")
zfs snapshot "$ds/root@identity"
iocell set istemplate=yes "$u" > "$workdir/template.log" 2>&1
tpl="$src/iocell/templates/safety-template"
[ "$(zfs get -H -o value guid "$tpl/root")" = "$root_guid" ]
[ "$(zfs get -H -o value jailed "$tpl/data")" = on ]
[ "$(uclcmd get -qf /iocell/templates/safety-template/config type)" = template ]
[ "$(uclcmd get -qf /iocell/templates/safety-template/config istemplate)" = yes ]
[ ! -L /iocell/tags/safety-template ]
echo 'PASS: successful template conversion preserves GUID, content and delegated state'

new_jail safety-template-off
off_ds="$new_ds"
zfs create -o mountpoint=none -o jailed=off "$off_ds/data"
iocell set "jail_zfs_dataset=$off_ds/data" "$new_uuid"
off_guid=$(zfs get -H -o value guid "$off_ds/root")
iocell set istemplate=yes "$new_uuid" > "$workdir/template-off.log" 2>&1
[ "$(zfs get -H -o value jailed "$src/iocell/templates/safety-template-off/data")" = off ]
[ "$(zfs get -H -o value guid "$src/iocell/templates/safety-template-off/root")" = "$off_guid" ]
echo 'PASS: forward template conversion also preserves delegated-off state'

clone=$(iocell create -e tag=safety-dependent)
clone_ds="$src/iocell/jails/$clone"
zfs destroy "$clone_ds/root"
zfs clone "$tpl/root@identity" "$clone_ds/root"
clone_guid=$(zfs get -H -o value guid "$clone_ds/root")
if printf 'y\n' | env PATH="$workdir/bin:$PATH" IOC_SAFETY_FAULT=origin \
    sh ./iocell clean -t > "$workdir/clean-query.log" 2>&1; then
    echo 'FAIL: cleanup ignored origin-query failure' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$clone_ds/root")" = "$clone_guid" ]
[ "$(zfs get -H -o value guid "$tpl/root")" = "$root_guid" ]
echo 'PASS: cleanup query failure returns nonzero without changing datasets'
if printf 'y\n' | iocell clean -t > "$workdir/clean-dependent.log" 2>&1; then
    echo 'FAIL: non-force cleanup accepted dependent clone' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$clone_ds/root")" = "$clone_guid" ]
[ "$(zfs get -H -o value guid "$tpl/root")" = "$root_guid" ]
echo 'PASS: non-force cleanup preserves template and dependent root clone'
zfs destroy "$clone_ds/root"
if printf 'y\n' | env PATH="$workdir/bin:$PATH" IOC_SAFETY_FAULT=race \
    IOC_SAFETY_TEMPLATE_ROOT="$tpl/root@identity" \
    IOC_SAFETY_RACE_DEST="$src/race-clone" sh ./iocell clean -t \
    > "$workdir/clean-race.log" 2>&1; then
    echo 'FAIL: cleanup destroyed a clone created after preflight' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$tpl/root")" = "$root_guid" ]
zfs list "$src/race-clone" >/dev/null
if printf 'y\n' | iocell clean -t > "$workdir/clean-outside.log" 2>&1; then
    echo 'FAIL: cleanup accepted a clone outside the jails namespace' >&2; exit 1
fi
echo 'PASS: cleanup preserves racing clones and clones outside the jails namespace'
iocell clean -f -t > "$workdir/clean-force.log" 2>&1
if zfs list "$tpl" >/dev/null 2>&1 || \
    zfs list "$src/race-clone" >/dev/null 2>&1; then
    echo 'FAIL: explicit force did not remove dependent roots' >&2; exit 1
fi
echo 'PASS: explicit forced template cleanup works'

new_jail safety-send
u="$new_uuid"; ds="$new_ds"; mp="$new_mp"
source_guid=$(zfs get -H -o value guid "$ds/root")
received="$dst/iocell/jails/$u/root"
read_received () {
    zfs set "mountpoint=$workdir/received" "$dst/iocell"
    zfs mount "$dst/iocell" 2>/dev/null || :
    zfs mount "$received" 2>/dev/null || :
    p=$(zfs get -H -o value mountpoint "$received")
    cat "$p/marker"
    zfs unmount "$received"
}
echo first > "$mp/root/marker"
iocell send "$dst" > "$workdir/send-first.log" 2>&1
[ "$(read_received)" = first ]
base=$(zfs list -H -d1 -t snapshot -o name -s creation "$src/iocell" | \
    grep "^$src/iocell@" | tail -1)
echo incremental > "$mp/root/marker"
zfs snapshot -r "$src/iocell@inc1"
iocell send -i "$base" -i "$src/iocell@inc1" "$dst" > "$workdir/send-i.log" 2>&1
[ "$(read_received)" = incremental ]
echo intermediate > "$mp/root/marker"; zfs snapshot -r "$src/iocell@inc2"
echo inclusive > "$mp/root/marker"; zfs snapshot -r "$src/iocell@inc3"
iocell send -I "$src/iocell@inc1" -I "$src/iocell@inc3" "$dst" > "$workdir/send-I.log" 2>&1
[ "$(read_received)" = inclusive ]
zfs list -t snapshot "$dst/iocell@inc2" >/dev/null
echo 'PASS: local -i and -I still deliver current content and intermediate snapshots'
# Full streams are tested against a fresh receiver, as with a new backup
# pool. Existing replicas use incremental streams (ZFS may reject a full
# overwrite when the receiver already has snapshots).
zfs destroy -r "$dst/iocell"
echo second > "$mp/root/marker"
iocell send "$dst" > "$workdir/send-second.log" 2>&1
[ "$(read_received)" = second ]
echo 'PASS: repeated full sends contain current content, not the first daily snapshot'
zfs destroy -r "$dst/iocell"
echo clean-send > "$mp/root/marker"
iocell send -c "$dst" > "$workdir/send-clean.log" 2>&1
[ "$(read_received)" = clean-send ]
echo second > "$mp/root/marker"
echo 'PASS: clean send takes its fresh snapshot after cleanup'
for fault in snapshot receive send-after; do
    if zfs list "$dst/iocell" >/dev/null 2>&1; then
        zfs destroy -r "$dst/iocell"
    fi
    if PATH="$workdir/bin:$PATH" IOC_SAFETY_FAULT="$fault" \
        iocell send -m "$dst" > "$workdir/failure-$fault.log" 2>&1; then
        echo "FAIL: $fault transfer reported success" >&2; exit 1
    fi
    [ "$(zfs get -H -o value guid "$ds/root")" = "$source_guid" ]
    [ "$(cat "$mp/root/marker")" = second ]
    [ "$(iocell get pool default)" = "$src" ]
    echo "PASS: $fault failure returns nonzero and retains active source/data"
done
if zfs list "$dst/iocell" >/dev/null 2>&1; then
    zfs destroy -r "$dst/iocell"
fi
if env PATH="$workdir/bin:$PATH" IOC_SAFETY_FAULT=activate \
    IOC_SAFETY_DESTROOT="$dst/iocell" sh ./iocell send -m "$dst" \
    > "$workdir/failure-activate.log" 2>&1; then
    echo 'FAIL: activation failure reported successful move' >&2; exit 1
fi
[ "$(zfs get -H -o value guid "$ds/root")" = "$source_guid" ]
p=$(zfs get -H -o value mountpoint "$ds/root")
[ "$(cat "$p/marker")" = second ]
iocell activate "$src" > "$workdir/reactivate.log" 2>&1
mp=$(zfs get -H -o value mountpoint "$ds")
zfs destroy -r "$dst/iocell"
echo 'PASS: activation failure retains source data and allows reactivation'
echo final > "$mp/root/marker"
iocell send -m "$dst" > "$workdir/move.log" 2>&1
if zfs list "$src/iocell" >/dev/null 2>&1; then
    echo 'FAIL: successful move left its source' >&2; exit 1
fi
[ "$(iocell get pool default)" = "$dst" ]
[ "$(iocell get tag "$u")" = safety-send ]
p=$(zfs get -H -o value mountpoint "$received")
[ "$(cat "$p/marker")" = final ]
echo 'PASS: successful move retains destination content and activates destination'
zpool status -x
