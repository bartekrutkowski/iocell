#!/bin/sh
# Real dispatch/native metadata, injected stop/ZFS errors and successful deletion.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
before=$(sha256 -q "$IOC_TEST_ROOT/.default")
workdir=$(mktemp -d /var/tmp/iocell-destroy-status-zfs.XXXXXX)
p=$(ioc_test_pool_name iocdst); first=$(uuidgen); second=$(uuidgen)
echo "Retained destroy logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
zfs create -o mountpoint="$workdir/tree" "$p/iocell"
zfs create "$p/iocell/templates"
root="$workdir/tree"
for id in "$first" "$second"; do
    zfs create -p "$p/iocell/jails/$id/root"
    printf 'host_hostuuid="%s";tag="%s";type="basejail";\n' "$id" "$id" > "$root/jails/$id/config"
    mkdir -p "$root/tags"; ln -s "$root/jails/$id" "$root/tags/$id"
    echo preserved > "$root/jails/$id/root/canary"
    cp "$root/jails/$id/config" "$workdir/$id.config"
    zfs get -H -o value guid "$p/iocell/jails/$id/root" > "$workdir/$id.guid"
done
zfs create "$p/iocell/base"; echo legacy > "$root/base/canary"
mkdir "$workdir/bin"
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
if [ "$DT_MODE" = origin ] && [ "$*" = "get -H -o value origin $DT_POOL/iocell/jails/$DT_FIRST" ]; then
    echo 'injected origin query failure' >&2; exit 44
fi
case "$1" in
    get|list) exec /sbin/zfs "$@" ;;
    destroy)
        for target; do :; done
        echo "$*" >> "$DT_EVENTS"
        if [ "$DT_MODE" != success ] && [ "$target" = "$DT_POOL/iocell/jails/$DT_FIRST" ]; then
            echo 'injected native destroy failure' >&2; exit 42
        fi
        case "$target" in "$DT_POOL/iocell/jails/$DT_FIRST") exec /sbin/zfs "$@" ;; esac ;;
esac
echo 'unexpected destructive operation' >&2; exit 99
WRAPPER
cat > "$workdir/bin/rm" <<'WRAPPER'
#!/bin/sh
case "$1" in -*r*|-*R*) echo 'recursive file deletion after failed ZFS destroy' >> "$DT_EVENTS"; exit 99 ;; esac
exec /bin/rm "$@"
WRAPPER
chmod +x "$workdir/bin/zfs" "$workdir/bin/rm"
cat > "$workdir/destroy.sh" <<'HELPER'
#!/bin/sh
set +u
. ./lib/ioc-globals
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-rc
. ./lib/ioc-zfs
. ./lib/ioc-cmd
pool="$DT_POOL"; iocroot="$DT_ROOT"
if [ "$DT_MODE" = stop ]; then __stop_jail () { echo 'injected stop failure' >&2; return 42; }; fi
__validate_cmd "$@" && __parse_cmd "$@"
HELPER
cleanup () {
    if jls -j "ioc-$first" jid >/dev/null 2>&1; then jail -r "ioc-$first"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
for mode in stop origin native; do
    : > "$workdir/events"; status=0
    if [ "$mode" = stop ]; then
        jail -c "name=ioc-$first" "path=$root/jails/$first/root" persist ip4=disable ip6=disable
        jid=$(jls -j "ioc-$first" jid)
    fi
    env PATH="$workdir/bin:$PATH" DT_POOL="$p" DT_ROOT="$root" DT_FIRST="$first" \
        DT_EVENTS="$workdir/events" DT_MODE="$mode" sh "$workdir/destroy.sh" \
        destroy -f "$first" "$second" > "$workdir/$mode.log" 2>&1 || status=$?
    want=42; [ "$mode" != origin ] || want=44
    [ "$status" = "$want" ]
    if [ "$mode" = stop ]; then
        [ ! -s "$workdir/events" ]; [ "$(jls -j "ioc-$first" jid)" = "$jid" ]
        jail -r "ioc-$first"
    elif [ "$mode" = origin ]; then
        [ ! -s "$workdir/events" ]
    else
        printf 'destroy -fr %s/iocell/jails/%s\n' "$p" "$first" > "$workdir/expected"
        cmp "$workdir/events" "$workdir/expected"
    fi
    for id in "$first" "$second"; do
        cmp "$root/jails/$id/config" "$workdir/$id.config"
        [ "$(cat "$root/jails/$id/root/canary")" = preserved ]
        [ "$(readlink "$root/tags/$id")" = "$root/jails/$id" ]
        [ "$(zfs get -H -o value guid "$p/iocell/jails/$id/root")" = "$(cat "$workdir/$id.guid")" ]
    done
    [ "$(cat "$root/base/canary")" = legacy ]
    echo "PASS: native destroy $mode failure preserves status, jails, aliases, config and data"
done
base_guid=$(zfs get -H -o value guid "$p/iocell/base")
zfs set mountpoint="$workdir/retained-base" "$p/iocell/base"
zfs rename "$p/iocell/base" "$p/retained-base"
: > "$workdir/events"
env PATH="$workdir/bin:$PATH" DT_POOL="$p" DT_ROOT="$root" DT_FIRST="$first" \
    DT_EVENTS="$workdir/events" DT_MODE=success sh "$workdir/destroy.sh" \
    destroy -f "$first" > "$workdir/success.log" 2>&1
if zfs list "$p/iocell/jails/$first" > "$workdir/removed.log" 2>&1; then exit 1; fi
[ ! -L "$root/tags/$first" ]
[ "$(cat "$root/jails/$second/root/canary")" = preserved ]
[ "$(cat "$workdir/retained-base/canary")" = legacy ]
[ "$(zfs get -H -o value guid "$p/retained-base")" = "$base_guid" ]
echo 'PASS: native successful destroy returns zero without a legacy base dataset'
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: native destroy preserves original activation'
zpool status -x
