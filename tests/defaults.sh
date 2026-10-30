#!/bin/sh
# Catch default-target jail lookup, lost inheritance/precedence, and unsafe writes.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-cmd
. ./lib/ioc-info
. ./lib/ioc-configure
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-defaults.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM
# JSON is valid UCL. Only the external UCL parser is replaced on non-FreeBSD.
cat > "$workdir/ucl.py" <<'PY'
import json, os, sys
args = sys.argv[1:]
command = args.pop(0)
path = output = None
unquoted = False
while args and args[0].startswith('-'):
    flag = args.pop(0)
    if flag == '--':
        break
    if flag in ('-f', '-qf'):
        path = args.pop(0)
        unquoted = unquoted or flag == '-qf'
    elif flag == '-o':
        output = args.pop(0)
    elif flag == '-t':
        assert args.pop(0) == 'string'
    else:
        assert flag in ('-u', '-q'), flag
try:
    with open(path) as stream:
        text = stream.read()
        data = json.loads(text) if text.strip() else {}
except (ValueError, OSError) as error:
    print(error, file=sys.stderr)
    sys.exit(9)
if command == 'get':
    value = data.get(args[0])
    print('null' if value is None else (value if unquoted else json.dumps(value)))
elif command == 'set':
    if os.environ.get('IOC_DEFAULT_TEST_FAIL') == 'yes':
        print('fixture parser/write failure', file=sys.stderr)
        sys.exit(42)
    assert len(args) == 2, args
    data[args[0]] = args[1]
    with open(output or path, 'w') as stream:
        json.dump(data, stream)
else:
    raise AssertionError(command)
PY
uclcmd () { python3 "$workdir/ucl.py" "$@"; }
mv () {
    [ "${IOC_DEFAULT_TEST_FAIL:-}" != rename ] || return 43
    command mv "$@"
}
uuidgen () { echo 22222222-2222-2222-2222-222222222222; }
__list_jails () { :; }
fgrep () { [ "$3" != /etc/devfs.rules ] && command fgrep "$@"; }
zfs () {
    printf '%s\n' "$*" >> "$state/zfs.trace"
    case "$1" in
        list) echo tank/iocell/releases/15.1-RELEASE ;;
        get) echo creation ;;
        create)
            [ "$2" = -p ] && [ "$#" = 3 ] || return 99
            mkdir -p "$iocroot/jails/$(basename "$(dirname "$3")")/root"
            ;;
        set) : ;;
        *) echo "Unexpected ZFS action: $*" >&2; return 99 ;;
    esac
}
prepare () {
    state="$workdir/$1"; iocroot="$state/iocell"
    mkdir -p "$iocroot/jails/existing/root"
    printf 'existing configuration\n' > "$iocroot/jails/existing/config"
    printf 'existing data\n' > "$iocroot/jails/existing/root/marker"
    cp "$iocroot/jails/existing/config" "$state/existing-before"
    cat > "$iocroot/.default" <<'JSON'
{"pool":"tank","vnet":"on","notes":"saved notes","priority":"99","compression":"off","tag":"old-default-tag","host_hostname":"old-host","host_hostuuid":"11111111-1111-1111-1111-111111111111","jail_zfs_dataset":"old/data","istemplate":"no","template":"none","type":"basejail"}
JSON
    cp "$iocroot/.default" "$state/default-before"
    : > "$state/zfs.trace"
    pool=tank; release=15.1-RELEASE; pkglist=none; count=1
    vnet=off; notes='built-in notes'; priority=99; tag=fresh-tag; host_hostname=fresh-host
    host_hostuuid=fresh-uuid; jail_zfs_dataset=fresh/data
    istemplate=no; template=none; type=basejail; compression=lz4
    origin=readonly; mountpoint=readonly; used=readonly
    CONF_NET='vnet host_hostname'
    CONF_JAIL=host_hostuuid; CONF_RCTL=''; CONF_FTP=''; CONF_GIT=''; CONF_SYNC=''
    CONF_CUSTOM='notes priority tag pool jail_zfs_dataset istemplate template type'
    CONF_ZFS='compression origin mountpoint used'
    unset iocset_vnet iocset_notes iocset_priority iocset_host_hostname
}
failed=0
for label in set set-equals inherit inherit-none inherit-null override \
    invalid-name empty missing-property invalid-bool managed-pool managed-uuid \
    readonly parse-failure malformed-create write-failure rename-failure; do
    prepare "$label"
    status=0; want=0
    case "$label" in
        set) args='notes=changed' ;;
        set-equals) args='notes=alpha=beta gamma' ;;
        inherit|override) args='' ;;
        inherit-none|inherit-null)
            value=${label#inherit-}
            uclcmd set -u -f "$iocroot/.default" -t string -- notes "$value"
            cp "$iocroot/.default" "$state/default-before"
            args='' ;;
        missing-property) args=''; want=1 ;;
        invalid-name) args='unknown_property=value'; want=1 ;;
        empty) args='notes='; want=1 ;;
        invalid-bool) args='vnet=invalid'; want=1 ;;
        managed-pool) args='pool=wrong'; want=1 ;;
        managed-uuid) args='host_hostuuid=wrong'; want=1 ;;
        readonly) args='origin=wrong'; want=1 ;;
        parse-failure|malformed-create)
            echo '{ broken' > "$iocroot/.default"
            cp "$iocroot/.default" "$state/default-before"
            args='notes=changed'; want=9 ;;
        write-failure) args='notes=changed'; want=42 ;;
        rename-failure) args='notes=changed'; want=43 ;;
    esac
    (
        set +e
        [ "$label" != write-failure ] || export IOC_DEFAULT_TEST_FAIL=yes
        [ "$label" != rename-failure ] || export IOC_DEFAULT_TEST_FAIL=rename
        case "$label" in
            inherit|inherit-none|inherit-null|malformed-create) __parse_cmd create -e ;;
            missing-property) __parse_cmd set default ;;
            override) __parse_cmd create -e vnet=off notes=explicit ;;
            *) __parse_cmd set "$args" default ;;
        esac
    ) > "$state/log" 2>&1 || status=$?
    if [ "$status" -ne "$want" ]; then
        echo "FAIL: $label status $status, expected $want"
        cat "$state/log"; failed=1; continue
    fi
    if [ "$want" -ne 0 ]; then
        cmp "$iocroot/.default" "$state/default-before" || { failed=1; continue; }
    else
        case "$label" in
            set|set-equals)
                expected=changed
                [ "$label" != set-equals ] || expected='alpha=beta gamma'
                [ "$(__get_jail_prop notes default)" = "$expected" ] || {
                    echo "FAIL: $label not persisted"; failed=1; continue;
                }
                ;;
            inherit|inherit-none|inherit-null|override)
                config="$iocroot/jails/22222222-2222-2222-2222-222222222222/config"
                expected_notes='saved notes'; expected_vnet=on
                case "$label" in
                    inherit-none) expected_notes=none ;;
                    inherit-null) expected_notes=null ;;
                esac
                if [ "$label" = override ]; then
                    expected_notes=explicit; expected_vnet=off
                fi
                [ "$(uclcmd get -qf "$config" notes)" = "$expected_notes" ] &&
                [ "$(uclcmd get -qf "$config" vnet)" = "$expected_vnet" ] &&
                [ "$(uclcmd get -qf "$config" tag)" = fresh-tag ] &&
                [ "$(uclcmd get -qf "$config" host_hostuuid)" = \
                    22222222-2222-2222-2222-222222222222 ] || {
                    echo "FAIL: $label inheritance, precedence or fresh identity"
                    cat "$state/log"; failed=1; continue;
                }
                cmp "$iocroot/.default" "$state/default-before" || exit 1
                ;;
        esac
    fi
    case "$label" in
        inherit|inherit-none|inherit-null|override) ;;
        *) [ ! -s "$state/zfs.trace" ] || {
            echo "FAIL: $label performed jail/ZFS actions"
            failed=1; continue;
        } ;;
    esac
    cmp "$iocroot/jails/existing/config" "$state/existing-before" || exit 1
    [ "$(cat "$iocroot/jails/existing/root/marker")" = 'existing data' ] || exit 1
    echo "PASS: defaults $label"
done
exit "$failed"
