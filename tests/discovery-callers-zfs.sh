#!/bin/sh
# Real metadata/discovery/consumer paths; stop at an injected native list error.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-discovery-callers.XXXXXX)
p=$(ioc_test_pool_name ioccons)
u=$(uuidgen); ds="$p/iocell/jails/$u"
echo "Retained discovery caller logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
zfs create -o mountpoint="$workdir/tree" "$p/iocell"
zfs create -p "$ds/root"
zfs create "$p/iocell/templates"
zfs create -p "$p/iocell/releases/15.1-RELEASE"
printf 'tag="fixture"; type="basejail"; release="15.1-RELEASE"; host_hostuuid="%s";\n' "$u" > "$workdir/tree/jails/$u/config"
printf 'ip4_autostart="10"; ip4_autoend="20"; ip4_autosubnet="24";\n' > "$workdir/tree/.default"
echo preserved > "$workdir/tree/jails/$u/root/canary"
cp "$workdir/tree/jails/$u/config" "$workdir/config-before"
zfs list -Hrt all -o name,guid "$p" > "$workdir/namespace-before"
mkdir "$workdir/bin"
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
case "$*" in
    "list -d1 -rH -o name $DC_POOL/iocell/jails $DC_POOL/iocell/templates")
        n=$(cat "$DC_STATE/count"); n=$((n+1)); echo "$n" > "$DC_STATE/count"
        if [ "$n" = "$DC_FAIL_AT" ]; then
            printf '%s\n' "$DC_DATASET"
            echo 'injected native discovery failure' >&2
            exit 42
        fi ;;
esac
case "$1" in list|get) exec /sbin/zfs "$@" ;;
    *) echo "unexpected zfs mutation $*" >> "$DC_STATE/actions"; exit 99 ;;
esac
WRAPPER
cat > "$workdir/bin/uclcmd" <<'WRAPPER'
#!/bin/sh
if [ "$1" != get ]; then echo 'unexpected UCL write' >> "$DC_STATE/actions"; exit 99; fi
exec /usr/local/bin/uclcmd "$@"
WRAPPER
chmod +x "$workdir/bin/zfs" "$workdir/bin/uclcmd"
cat > "$workdir/consumer.sh" <<'HELPER'
#!/bin/sh
for lib in globals common info help rctl network upgrade configure; do . "./lib/ioc-$lib"; done
pool="$DC_POOL"; iocroot="$DC_ROOT"
__check_basejail () { echo 'unexpected migration/mount' >> "$DC_STATE/actions"; return 99; }
__reset_jail_props () { echo 'unexpected reset' >> "$DC_STATE/actions"; return 99; }
case "$1" in
    list) __list_jails '' ;; templates) __list_jails -t ;;
    warden) __list_jails_warden ;; warden-dispatch) __list_jails --warden ;;
    rctl) __rctl_inuse_all ;; autoip) __get_autoip4 fixture "$DC_DATASET" ;;
    reset) __reset_jail_props_all ;; show) __show notes ;;
    disk) __print_disk ;; upgrade) __upgrade fixture ;;
esac
HELPER
for label in list templates warden warden-dispatch rctl autoip reset show disk upgrade; do
    state="$workdir/$label"; mkdir "$state"; echo 0 > "$state/count"
    : > "$state/actions"; fail_at=1; status=0
    [ "$label" != upgrade ] || fail_at=2
    env PATH="$workdir/bin:$PATH" DC_POOL="$p" DC_ROOT="$workdir/tree" \
        DC_DATASET="$ds" DC_STATE="$state" DC_FAIL_AT="$fail_at" \
        sh "$workdir/consumer.sh" "$label" > "$state/log" 2>&1 || status=$?
    [ "$status" = 42 ]
    [ ! -s "$state/actions" ]
    grep -q 'injected native discovery failure' "$state/log"
    cmp "$workdir/config-before" "$workdir/tree/jails/$u/config"
    [ "$(cat "$workdir/tree/jails/$u/root/canary")" = preserved ]
    zfs list -Hrt all -o name,guid "$p" > "$state/namespace-after"
    cmp "$workdir/namespace-before" "$state/namespace-after"
    echo "PASS: native $label preserves failed discovery status, config, data and GUIDs"
done
