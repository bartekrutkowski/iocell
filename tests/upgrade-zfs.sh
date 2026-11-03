#!/bin/sh
# Real basejail merge/backout: binaries alone cannot establish upgrade success.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
: "${IOC_TEST_RELEASE:?Set IOC_TEST_RELEASE to the fetched target release}"
old=${IOC_TEST_OLD_RELEASE:-14.5-RELEASE}
[ "$old" != "$IOC_TEST_RELEASE" ] || exit 1
for rel in "$old" "$IOC_TEST_RELEASE"; do
    [ -f "$IOC_TEST_ROOT/releases/$rel/root/usr/src/Makefile" ] || {
        ioc_test_error "upgrade requires complete source for $rel"; exit 1;
    }
done
workdir=$(mktemp -d /var/tmp/iocell-upgrade.XXXXXX)
echo "Retained upgrade/backout logs: $workdir"
id=''
cleanup () {
    [ -z "$id" ] || sh ./iocell stop "$id" >> "$workdir/stop.log" 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$workdir/bin"
cat > "$workdir/bin/chroot" <<'WRAPPER'
#!/bin/sh
case "${IOC_UPGRADE_FAULT:-}:$2:${3:-}" in
    aliases:newaliases:*)
        echo partial > "$1/etc/upgrade-preserved"
        echo 'injected mail alias rebuild failure' >&2
        exit 53 ;;
    failure:etcupdate:-F)
        echo partial > "$1/etc/upgrade-preserved"
        echo 'injected etcupdate tree-build failure' >&2
        exit 42 ;;
    conflict:etcupdate:-F)
        # Real etcupdate merge; a tiny vendor tree creates one genuine conflict.
        exec /usr/sbin/chroot "$1" etcupdate -t /var/db/upgrade-conflict-new.tbz ;;
    conflict:etcupdate:resolve)
        # Real interactive resolver: deliberately postpone the single conflict.
        printf 'p\n' | /usr/sbin/chroot "$@"
        exit $? ;;
esac
exec /usr/sbin/chroot "$@"
WRAPPER
chmod +x "$workdir/bin/chroot"
for mode in ${IOC_TEST_UPGRADE_MODES:-failure aliases conflict success}; do
    tag="upgrade-$mode-$(uuidgen)"
    sh ./iocell create "release=$old" "tag=$tag" > "$workdir/$mode.create" 2>&1
    id=$(sh ./iocell get host_hostuuid "$tag")
    ds="$IOC_TEST_POOL/iocell/jails/$id"
    mp=$(zfs get -H -o value mountpoint "$ds")
    echo original > "$mp/root/etc/upgrade-preserved"
    if [ -d "$mp/root/var/spool/mqueue" ]; then
        mv "$mp/root/var/spool/mqueue" "$mp/mqueue.before"
    fi
    if [ "$mode" = conflict ]; then
        mv "$mp/root/var/db/etcupdate/current" "$mp/etcupdate-current.before"
        mkdir -p "$mp/root/var/db/etcupdate/current/etc" "$workdir/new/etc"
        echo ancestor > "$mp/root/var/db/etcupdate/current/etc/upgrade-preserved"
        echo vendor > "$workdir/new/etc/upgrade-preserved"
        tar -cjf "$mp/root/var/db/upgrade-conflict-new.tbz" -C "$workdir/new" .
    fi
    cp -p "$mp/config" "$workdir/$mode.config"
    cp -p "$mp/root/etc/defaults/rc.conf" "$workdir/$mode.rc.conf"
    guid=$(zfs get -H -o value guid "$ds/root")
    status=0
    if [ "$mode" != success ]; then
        env PATH="$workdir/bin:$PATH" IOC_UPGRADE_FAULT="$mode" \
            sh ./iocell upgrade "$id" \
            "release=$IOC_TEST_RELEASE" > "$workdir/$mode.log" 2>&1 || status=$?
        expected=42
        [ "$mode" != aliases ] || expected=53
        [ "$mode" != conflict ] || expected=1
        [ "$status" = "$expected" ]
        if [ "$mode" = conflict ]; then
            grep -q 'unresolved configuration conflicts:' "$workdir/$mode.log"
            grep -q 'C /etc/upgrade-preserved' "$workdir/$mode.log"
        fi
        cmp "$mp/config" "$workdir/$mode.config"
        cmp "$mp/root/etc/defaults/rc.conf" "$workdir/$mode.rc.conf"
        [ "$(sh ./iocell get release "$id")" = "$old" ]
        if grep -q 'upgraded successfully' "$workdir/$mode.log"; then exit 1; fi
    else
        target="$IOC_TEST_ROOT/releases/$IOC_TEST_RELEASE/root/etc/defaults/rc.conf"
        if cmp -s "$mp/root/etc/defaults/rc.conf" "$target"; then
            ioc_test_error 'upgrade fixture does not distinguish old/new defaults'; exit 1
        fi
        sh ./iocell upgrade "$id" "release=$IOC_TEST_RELEASE" \
            > "$workdir/$mode.log" 2>&1
        cmp "$mp/root/etc/defaults/rc.conf" "$target"
        [ -d "$mp/root/var/spool/mqueue" ]
        [ "$(sh ./iocell get release "$id")" = "$IOC_TEST_RELEASE" ]
        output=$(sh ./iocell start "$id" 2>&1)
        printf '%s\n' "$output" > "$workdir/boot.log"
        sh ./iocell exec "$id" /usr/sbin/etcupdate status > "$workdir/merge-status"
        if grep -q '^[[:space:]]*C[[:space:]]' "$workdir/merge-status"; then exit 1; fi
        sh ./iocell exec "$id" /bin/freebsd-version -u > "$workdir/version"
        grep -F "${IOC_TEST_RELEASE}" "$workdir/version"
        sh ./iocell stop "$id" >> "$workdir/stop.log" 2>&1
    fi
    [ "$(cat "$mp/root/etc/upgrade-preserved")" = original ]
    [ "$(zfs get -H -o value guid "$ds/root")" = "$guid" ]
    [ -d "$mp/etc.old" ] && [ -f "$mp/config.old" ]
    zfs list -H -t snapshot -o name -r "$ds" > "$workdir/$mode.snapshots"
    grep -F "$ds/root@ioc-upgrade_" "$workdir/$mode.snapshots"
    mount -p > "$workdir/$mode.mounts"
    if awk -v root="$mp/root" '$3 != "zfs" && ($2 == root || index($2,root "/") == 1) {found=1} END {exit !found}' \
        "$workdir/$mode.mounts"; then exit 1; fi
    echo "PASS: actual $mode upgrade preserves config/data/GUID and recovery state"
done
