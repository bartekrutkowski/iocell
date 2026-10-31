#!/bin/sh
# Native empty-release cleanup must retain snapshots and unrelated data.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-plugin-release-zfs.XXXXXX)
p=$(ioc_test_pool_name iocpr)
echo "Retained plugin release logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
zfs create -o mountpoint="$workdir/tree" "$p/iocell"
zfs create "$p/iocell/releases"
cat > "$workdir/cleanup.sh" <<'HELPER'
#!/bin/sh
. ./lib/ioc-common
. ./lib/ioc-git
pool="$PR_POOL"; iocroot="$PR_ROOT"
__remove_empty_plugin_release "$1"
HELPER
for mode in empty snapshot child parent-data unmounted; do
    ds="$p/iocell/releases/$mode"; root="$workdir/tree/releases/$mode/root"
    zfs create -p "$ds/root"
    guid=$(zfs get -H -o value guid "$ds/root")
    case "$mode" in
        snapshot)
            echo saved-data > "$root/canary"
            zfs snapshot "$ds/root@saved"; rm "$root/canary"
            snap_guid=$(zfs get -H -o value guid "$ds/root@saved") ;;
        child) zfs create "$ds/other"; echo keep > "$workdir/tree/releases/$mode/other/canary" ;;
        parent-data) echo keep > "$workdir/tree/releases/$mode/canary" ;;
        unmounted) zfs unmount "$ds/root" ;;
    esac
    status=0
    env PR_POOL="$p" PR_ROOT="$workdir/tree" sh "$workdir/cleanup.sh" "$mode" \
        > "$workdir/$mode.log" 2>&1 || status=$?
    if [ "$mode" = empty ]; then
        [ "$status" = 0 ]
        if zfs list "$ds" > "$workdir/removed.log" 2>&1; then
            echo 'FAIL: native empty release was not removed'; exit 1
        fi
    else
        [ "$status" = 1 ]
        [ "$(zfs get -H -o value guid "$ds/root")" = "$guid" ]
        case "$mode" in
            snapshot)
                [ "$(zfs get -H -o value guid "$ds/root@saved")" = "$snap_guid" ]
                [ "$(cat "$root/.zfs/snapshot/saved/canary")" = saved-data ] ;;
            child) [ "$(cat "$workdir/tree/releases/$mode/other/canary")" = keep ] ;;
            parent-data) [ "$(cat "$workdir/tree/releases/$mode/canary")" = keep ] ;;
            unmounted) [ "$(zfs get -H -o value mounted "$ds/root")" = no ] ;;
        esac
    fi
    echo "PASS: native plugin release cleanup $mode"
done
zpool status -x
