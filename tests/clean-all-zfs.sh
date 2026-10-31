#!/bin/sh
# Combined -a modes must wipe once, and storage failures must retain data.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
before=$(sha256 -q "$IOC_TEST_ROOT/.default")
workdir=$(mktemp -d /var/tmp/iocell-clean-all.XXXXXX)
p=$(ioc_test_pool_name iocall)
echo "Retained cleanup logs/vdev: $workdir; pool: $p"
truncate -s 128M "$workdir/pool.vdev"
zpool create -O mountpoint=none "$p" "$workdir/pool.vdev"
mkdir "$workdir/bin"
cat > "$workdir/bin/zfs" <<'WRAPPER'
#!/bin/sh
if [ "$1" = destroy ]; then
    echo "$*" >> "$CA_TRACE"
    if [ "$CA_MODE" = native ]; then echo 'injected cleanup destroy failure' >&2; exit 42; fi
fi
exec /sbin/zfs "$@"
WRAPPER
cat > "$workdir/bin/rm" <<'WRAPPER'
#!/bin/sh
case "$1" in -*r*|-*R*) echo 'recursive removal after cleanup' >> "$CA_TRACE"; exit 99 ;; esac
exec /bin/rm "$@"
WRAPPER
chmod +x "$workdir/bin/zfs" "$workdir/bin/rm"
cat > "$workdir/clean.sh" <<'HELPER'
#!/bin/sh
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-rc
. ./lib/ioc-zfs
. ./lib/ioc-cmd
pool="$CA_POOL"; iocroot="$CA_ROOT"
if [ "$CA_MODE" = stop ]; then __stop_jail_all () { return 43; }; fi
__validate_cmd clean "$@" && __parse_cmd clean "$@"
HELPER
failed=0
for mode in first last repeated native stop; do
    root="$workdir/$mode"
    zfs create -o mountpoint="$root" "$p/iocell"
    zfs create -p "$p/iocell/jails/fixture"
    zfs create "$p/iocell/templates"
    echo preserved > "$root/jails/fixture/canary"
    guid=$(zfs get -H -o value guid "$p/iocell/jails/fixture")
    trace="$workdir/$mode.trace"; : > "$trace"; status=0; want=0
    case "$mode" in first) set -- -a -j -f ;; last) set -- -j -t -f -a ;;
        repeated) set -- -a -a -f ;; native) set -- -a -f; want=42 ;;
        stop) set -- -a -f; want=43 ;; esac
    env PATH="$workdir/bin:$PATH" CA_POOL="$p" CA_ROOT="$root" CA_MODE="$mode" \
        CA_TRACE="$trace" sh "$workdir/clean.sh" "$@" > "$workdir/$mode.log" 2>&1 || status=$?
    if [ "$status" != "$want" ]; then
        echo "FAIL: native cleanup $mode status=$status expected=$want"; failed=1
    elif [ "$want" = 0 ]; then
        printf 'destroy -rRf %s/iocell\n' "$p" > "$workdir/expected"
        cmp "$trace" "$workdir/expected"
        if zfs list "$p/iocell" >/dev/null 2>&1; then exit 1; fi
        echo "PASS: native clean -a dominates $mode mode combinations"
    else
        [ "$(cat "$root/jails/fixture/canary")" = preserved ]
        [ "$(zfs get -H -o value guid "$p/iocell/jails/fixture")" = "$guid" ]
        echo "PASS: native cleanup $mode failure preserves data and GUID"
    fi
    if zfs list "$p/iocell" >/dev/null 2>&1; then
        zfs rename "$p/iocell" "$p/retained-$mode"
    fi
done
[ "$(sha256 -q "$IOC_TEST_ROOT/.default")" = "$before" ]
zpool status -x
exit "$failed"
