#!/bin/sh
# Real legacy layout, migration preflight and callers; OS/network work is inert.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set the release name for fixture metadata}"
[ -x /usr/local/bin/git ] || {
    ioc_test_error 'install git for the plugin caller fixtures'; exit 1;
}
before=$(sha256 -q "$IOC_TEST_ROOT/.default")
workdir=$(mktemp -d /var/tmp/iocell-migration-callers-zfs.XXXXXX)
p=$(ioc_test_pool_name iocmc); uuid=$(uuidgen)
echo "Retained migration logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
zfs create -o mountpoint="$workdir/tree" "$p/iocell"
zfs create -p "$p/iocell/jails/$uuid/root"
zfs create "$p/iocell/templates"
root="$workdir/tree"; ds="$p/iocell/jails/$uuid"; mp="$root/jails/$uuid"
cp "$IOC_TEST_ROOT/.default" "$root/.default"
for i in $(seq 1 17); do zfs create "$ds/root/legacy-$i"; done
mkdir -p "$root/log" "$root/releases/$IOC_TEST_RELEASE/root/etc" \
    "$root/releases/14.5-RELEASE/root" "$mp/root/etc"
: > "$root/releases/$IOC_TEST_RELEASE/root/etc/resolv.conf"
: > "$root/releases/$IOC_TEST_RELEASE/root/etc/freebsd-update.conf"
echo fixture > "$root/releases/14.5-RELEASE/root/marker"
echo preserved > "$mp/root/etc/canary"
: > "$mp/root/.mtree"
cat > "$workdir/helper.sh" <<'HELPER'
#!/bin/sh
set +u
. ./lib/ioc-globals
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-configure
. ./lib/ioc-zfs
. ./lib/ioc-hacks
. ./lib/ioc-rc
. ./lib/ioc-upgrade
. ./lib/ioc-git
pool="$MC_POOL"; iocroot="$MC_ROOT"; uuid="$MC_UUID"
ds="$pool/iocell/jails/$uuid"; mode="$1"
if [ "$mode" = configure ]; then
    host_hostuuid="$uuid"; release="$MC_RELEASE"; type=basejail
    tag='invalid@template'; template=yes; istemplate=no; hack88=0
    vnet=off; bpf=off; dhcp=off; mount_procfs=0; mount_linprocfs=0
    __configure_jail generate "$uuid" "$ds" "$iocroot/jails/$uuid"
    exit $?
fi
forbidden () { echo "$*" >> "$MC_STATE/forbidden"; exit 99; }
zfs () {
    case "$1" in
        get|list) /sbin/zfs "$@" ;;
        *) forbidden "zfs $*" ;;
    esac
}
jail () { forbidden "jail $*"; }
mtree () {
    case "$mode" in
        *-ok) echo completed > "$MC_STATE/continued" ;;
        *) forbidden "mtree $*" ;;
    esac
}
mount () { [ "$mode" != start ] || forbidden "mount $*"; }
umount () { :; }; chroot () { :; }
git () {
    case "$*" in
        'branch -r') printf 'origin/master\norigin/%s-amd64\n' "${MC_RELEASE%-RELEASE}" ;;
    esac
}
__spinner () { eval "$2"; }
__create_jail () { uuid="$MC_UUID"; }
__fetch_release () {
    jobs -p > "$MC_STATE/spinner-pids"
    mv "$MC_STATE/release-stash" "$iocroot/releases/$MC_RELEASE"
}
case "$mode" in *-ok) __check_basejail () { return 0; } ;; esac
case "$mode" in *-setfail)
    __ucl_set () { __error 'fixture release write failure'; return 42; } ;;
esac
case "$mode" in
    start) __start_jail "$uuid" ;;
    update) __update x x x "$uuid" ;;
    upgrade) iocset_release="$MC_RELEASE"; __upgrade "$uuid" ;;
    plugin-*) iocset_release=14.5-RELEASE; __fetch_plugin fixture/plugin ;;
esac
HELPER
backend () {
    env MC_POOL="$p" MC_ROOT="$root" MC_UUID="$uuid" \
        MC_RELEASE="$IOC_TEST_RELEASE" MC_STATE="$workdir" \
        sh "$workdir/helper.sh" "$1"
}
echo '{}' > "$mp/config"
backend configure > "$workdir/configure.log" 2>&1
[ "$(uclcmd get -qf "$mp/config" host_hostuuid)" = "$uuid" ]
[ "$(uclcmd get -qf "$mp/config" type)" = basejail ]
[ "$(uclcmd get -qf "$mp/config" template)" = yes ]
[ "$(uclcmd get -qf "$mp/config" tag)" = 'invalid@template' ]
cp "$mp/config" "$workdir/config-before"
zfs get -rHp -o name,value guid "$ds" | sort > "$workdir/guids-before"
failed=0
for mode in start update upgrade plugin-existing plugin-fetched \
    plugin-existing-setfail plugin-fetched-setfail plugin-existing-ok plugin-fetched-ok; do
    : > "$workdir/forbidden"; rm -f "$workdir/continued"; status=0; want=1
    case "$mode" in *-ok) want=0 ;; *-setfail) want=42 ;; esac
    case "$mode" in plugin-fetched*)
        mv "$root/releases/$IOC_TEST_RELEASE" "$workdir/release-stash" ;;
    esac
    backend "$mode" > "$workdir/$mode.log" 2>&1 || status=$?
    if [ "$status" != "$want" ] || [ -s "$workdir/forbidden" ]; then
        echo "FAIL: native $mode status=$status expected=$want or ran forbidden work"
        failed=1
    elif [ "$want" = 1 ] && \
        ! grep -q 'safe template dataset name' "$workdir/$mode.log"; then
        echo "FAIL: native $mode hid the legacy migration rejection"
        failed=1
    elif [ "$want" = 42 ] && \
        ! grep -q 'fixture release write failure' "$workdir/$mode.log"; then
        echo "FAIL: native $mode hid the release write failure"; failed=1
    elif [ "$want" = 0 ] && [ ! -s "$workdir/continued" ]; then
        echo "FAIL: native $mode skipped normal plugin completion"
        failed=1
    elif ! cmp -s "$mp/config" "$workdir/config-before"; then
        echo "FAIL: native $mode changed configuration on failed preflight"
        failed=1
    else
        echo "PASS: native $mode preserves status and migration phase boundaries"
    fi
    case "$mode" in plugin-fetched|plugin-fetched-setfail)
        grep -q '^  ERROR:' "$workdir/$mode.log" || {
            echo "FAIL: native $mode wrote diagnostics on the spinner line"; failed=1;
        } ;;
    esac
    case "$mode" in plugin-fetched*)
        [ -s "$workdir/spinner-pids" ] || {
            echo "FAIL: native $mode did not exercise the release-fetch spinner"
            failed=1
        } ;;
    esac
    if [ -f "$workdir/spinner-pids" ]; then
        while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "FAIL: native $mode left a release-fetch spinner alive"
                kill "$pid" || :; failed=1
            fi
        done < "$workdir/spinner-pids"
    fi
done
zfs get -rHp -o name,value guid "$ds" | sort > "$workdir/guids-after"
cmp "$workdir/guids-before" "$workdir/guids-after"
[ "$(cat "$mp/root/etc/canary")" = preserved ]
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
echo 'PASS: native failed legacy callers preserve dataset GUIDs, data and activation'
zpool status -x
exit "$failed"
