#!/bin/sh
# Real cleanup must preserve independently retained template data and aliases.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
workdir=$(mktemp -d /var/tmp/iocell-clean-jails.XXXXXX)
p=$(ioc_test_pool_name ioccj)
echo "Retained jail cleanup logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
cat > "$workdir/clean.sh" <<'SH'
#!/bin/sh
for f in lib/ioc-*; do . "./$f"; done
pool="$CJ_POOL"; iocroot="$CJ_ROOT"; _force=1
__stop_jail_all () { [ "$CJ_FAULT" != stop ] || return 43; }
zfs () {
    if [ "$CJ_FAULT" = destroy ] && [ "$1" = destroy ]; then return 42; fi
    /sbin/zfs "$@"
}
__clean_jails
SH
for fault in none internal destroy stop dependent; do
    root="$workdir/$fault"
    jail=$(uuidgen); template=$(uuidgen)
    zfs create -o mountpoint="$root" "$p/iocell"
    zfs create -p "$p/iocell/jails/$jail/root"
    zfs create -p "$p/iocell/templates/kept/root"
    mkdir "$root/tags"
    printf 'host_hostuuid="%s"; tag="retagged-template"; type="template"; istemplate="yes";\n' \
        "$template" > "$root/templates/kept/config"
    echo jail > "$root/jails/$jail/root/canary"
    echo template > "$root/templates/kept/root/canary"
    ln -s "$root/jails/$jail" "$root/tags/jail"
    ln -s ../templates/kept "$root/tags/retagged-template"
    cp "$root/templates/kept/config" "$workdir/$fault.config"
    guid=$(zfs get -H -o value guid "$p/iocell/templates/kept/root")
    if [ "$fault" = dependent ] || [ "$fault" = internal ]; then
        zfs snapshot "$p/iocell/jails/$jail/root@ioc-send-used"
        if [ "$fault" = dependent ]; then
            zfs clone "$p/iocell/jails/$jail/root@ioc-send-used" "$p/protected-clone"
        else
            inside=$(uuidgen)
            zfs create "$p/iocell/jails/$inside"
            zfs clone "$p/iocell/jails/$jail/root@ioc-send-used" "$p/iocell/jails/$inside/root"
        fi
    elif [ "$fault" = stop ]; then
        zfs snapshot "$p/iocell/jails/$jail/root@ioc-send-preserved"
    fi
    status=0
    env CJ_POOL="$p" CJ_ROOT="$root" CJ_FAULT="$fault" \
        sh "$workdir/clean.sh" > "$workdir/$fault.log" 2>&1 || status=$?
    [ -L "$root/tags/retagged-template" ]
    [ "$(cat "$root/templates/kept/root/canary")" = template ]
    [ "$(zfs get -H -o value guid "$p/iocell/templates/kept/root")" = "$guid" ]
    cmp "$root/templates/kept/config" "$workdir/$fault.config"
    if [ "$fault" = none ] || [ "$fault" = internal ]; then
        [ "$status" = 0 ] && [ ! -L "$root/tags/jail" ]
        if zfs list "$p/iocell/jails" >/dev/null 2>&1; then exit 1; fi
    else
        case "$fault" in destroy) [ "$status" = 42 ] ;;
            stop) [ "$status" = 43 ]; zfs list -t snapshot "$p/iocell/jails/$jail/root@ioc-send-preserved" >/dev/null ;;
            dependent) [ "$status" != 0 ]; zfs list "$p/protected-clone" >/dev/null ;;
        esac
        [ -L "$root/tags/jail" ]
        [ "$(cat "$root/jails/$jail/root/canary")" = jail ]
    fi
    echo "PASS: native clean-j $fault preserves unrelated template state"
    zfs rename "$p/iocell" "$p/retained-$fault"
done
