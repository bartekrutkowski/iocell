#!/bin/sh
# Real start phases must return failures, stop later work and clean by jail type.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-rc
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-start-failures.XXXXXX")
trap 'if [ "$failed" = 0 ]; then rm -rf "$workdir"; else echo "Retained: $workdir"; fi' EXIT
pool=tank; hostid=fixture-host
fixture_uuid=11111111-1111-1111-1111-111111111111
fixture_ds="tank/iocell/jails/$fixture_uuid"
__find_jail () { [ "$fault" != lookup ] || return 42; echo "$fixture_ds"; }
__check_name () { echo "$fixture_uuid"; }
__hack88_mount () { :; }
__is_running () { [ "$fault" != running ] || echo 1; }
__get_jail_prop () {
    case "$1" in
        type) echo "$kind" ;; tag) echo fixture ;;
        hostid) [ "$fault" != hostid ] && echo fixture-host || echo another-host ;;
        mountpoint) echo "$fixture_mp" ;; release) echo fixture-RELEASE ;;
        istemplate) [ "$kind" != template ] && echo no || echo yes ;;
        vnet) case "$fault" in legacy|affinity|services|success|dhcp-vnet) echo off ;; *) echo on ;; esac ;;
        dhcp) case "$fault" in dhcp-*) echo on ;; *) echo off ;; esac ;;
        interfaces) [ "$fault" != interfaces ] || echo malformed ;;
        bpf|jail_zfs) echo off ;;
        cpuset) [ "$fault" != affinity ] && echo off || echo 0 ;;
        exec_start) echo /bin/fixture ;; *) echo 0 ;;
    esac
}
__start_jail_all () { echo all >> "$trace"; return 44; }
__check_basejail () { echo mount-base >> "$trace"; [ "$fault" != migrate ] || return 46; }
__mount_basejail () { echo mount-base >> "$trace"; }
__mount_istemplate () { echo mount-template >> "$trace"; }
__umount_basejail () {
    [ "$*" = "$fixture_uuid $fixture_ds" ] || return 98
    echo cleanup-base >> "$trace"; return 91
}
__umount_istemplate () {
    [ "$*" = fixture ] || return 98
    echo cleanup-template >> "$trace"; return 91
}
__vnet_start () { echo kernel >> "$trace"; [ "$fault" != kernel ] || return 42; }
__networking () { echo network >> "$trace"; [ "$fault" != network ] || return 43; }
__legacy_start () { echo legacy >> "$trace"; [ "$fault" != legacy ] || return 45; }
__rctl_limits () { echo limits >> "$trace"; }
__resolv_conf () { echo resolver >> "$trace"; }
__set_jail_prop () { echo saved >> "$trace"; }
zfs () { echo 'fixture origin - local'; }
jls () { :; }; fgrep () { return 1; }
uname () { echo FreeBSD; }
sysctl () { [ "$fault" != unsupported ] || return 0; echo 1; }
cpuset () { echo affinity >> "$trace"; return 47; }
setfib () { echo services >> "$trace"; [ "$fault" != services ] || return 48; }
failed=0
for fault in lookup all interfaces hostid dhcp-vnet dhcp-bpf running migrate \
    kernel network unsupported legacy affinity services success ignored-template; do
    kinds=basejail
    case "$fault" in kernel|network|unsupported|legacy|affinity|services)
        kinds='basejail clonejail template thickjail' ;;
        ignored-template) kinds=template ;;
    esac
    for kind in $kinds; do
        state="$workdir/$fault-$kind"; iocroot="$state/tree"
        fixture_mp="$iocroot/jails/$fixture_uuid"
        mkdir -p "$fixture_mp/root/dev" "$fixture_mp/root/etc" "$iocroot/log"
        echo preserved > "$fixture_mp/root/canary"
        trace="$state/trace"; : > "$trace"; : > "$state/expected"
        _force=1; [ "$fault" != ignored-template ] || _force=0
        name="$fixture_uuid"; want=1
        case "$fault" in lookup|kernel) want=42 ;; network) want=43 ;;
            all) name=ALL; want=44 ;; legacy) want=45 ;; migrate) want=46 ;;
            affinity) want=47 ;; services) want=48 ;;
            success|ignored-template) want=0 ;;
        esac
        case "$fault" in
            lookup|interfaces|hostid|dhcp-*|running|ignored-template) ;;
            all) echo all >> "$state/expected" ;;
            *)
                case "$kind" in basejail|clonejail) echo mount-base >> "$state/expected" ;;
                    template) echo mount-template >> "$state/expected" ;;
                esac
                case "$fault" in
                    migrate|unsupported) ;;
                    kernel) echo kernel >> "$state/expected" ;;
                    network) printf 'kernel\nnetwork\n' >> "$state/expected" ;;
                    *) echo legacy >> "$state/expected"
                       if [ "$fault" != legacy ]; then echo limits >> "$state/expected"; fi
                       case "$fault" in affinity) echo affinity >> "$state/expected" ;;
                           services|success) printf 'resolver\nservices\n' >> "$state/expected" ;;
                       esac ;;
                esac
                if [ "$fault" = success ]; then echo saved >> "$state/expected"
                elif [ "$fault" != migrate ]; then
                    case "$kind" in basejail|clonejail) echo cleanup-base >> "$state/expected" ;;
                        template) echo cleanup-template >> "$state/expected" ;;
                    esac
                fi ;;
        esac
        status=0
        (
            set +e
            __start_jail "$name"
            result=$?
            echo "$result" > "$state/returned"
            wait
            exit "$result"
        ) > "$state/log" 2>&1 || status=$?
        if [ "$status" != "$want" ] || [ ! -f "$state/returned" ] ||
            [ "$(cat "$state/returned")" != "$want" ] ||
            ! cmp -s "$trace" "$state/expected" ||
            [ "$(cat "$fixture_mp/root/canary")" != preserved ]; then
            echo "FAIL: start $fault/$kind did not return $want or crossed its phase boundary ($status)"
            failed=1
        else echo "PASS: start $fault/$kind returns status and preserves phase/cleanup boundaries"; fi
    done
done
exit "$failed"
