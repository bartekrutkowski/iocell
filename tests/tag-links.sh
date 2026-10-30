#!/bin/sh
# Real symlink/file effects for absolute and altroot-relative tag replacement.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-tags.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
pool=tank; oldid=11111111-1111-1111-1111-111111111111
newid=22222222-2222-2222-2222-222222222222
CONF_NET=''; CONF_JAIL=''; CONF_RCTL=''; CONF_CUSTOM=tag
CONF_SYNC=''; CONF_FTP=''; CONF_GIT=''; CONF_ZFS=''
date () { echo 2026-01-01@00:00:00; }
zpool () { echo "$altroot"; }
zfs () { for last; do :; done; echo "$iocroot/jails/${last##*/}"; }
__check_name () { echo "$newid"; }
__get_jail_prop () {
    case "$1" in type) echo basejail ;; mountpoint) echo "$iocroot/jails/$newid" ;; esac
}
uclcmd () {
    input=''; output=''; operation=$1; shift
    while [ "$#" -gt 0 ]; do
        case "$1" in -f|-qf) input=$2; shift 2 ;; -o) output=$2; shift 2 ;;
            -t) shift 2 ;; --) shift; break ;; -*) shift ;; *) break ;; esac
    done
    if [ "$operation" = get ]; then awk -F= '$1=="tag" {print $2}' "$input"; return; fi
    [ "$fault" != writer ] || return 6
    [ -n "$output" ] || output="$input"
    printf 'tag=%s\n' "$2" > "$output"
}
ln () {
    [ "$fault" != link ] || [ "$1" != -sfn ] || return 7
    command ln "$@"
}
failed=0
for label in absolute relative collision writer link foreign broken file; do
    iocroot="$workdir/$label/iocell"; altroot=-; fault=none
    old="$iocroot/jails/$oldid"; new="$iocroot/jails/$newid"
    mkdir -p "$old" "$new" "$iocroot/tags"
    echo tag=shared > "$old/config"; echo tag=original > "$new/config"
    case "$label" in
        relative) altroot="$workdir/$label"; ln -s "../jails/$oldid" "$iocroot/tags/shared" ;;
        collision)
            ln -s "$old" "$iocroot/tags/shared"
            ln -s "$old" "$iocroot/tags/2026-01-01@00:00:00" ;;
        foreign)
            mkdir "$workdir/unmanaged"; echo tag=untouched > "$workdir/unmanaged/config"
            ln -s "$workdir/unmanaged" "$iocroot/tags/shared" ;;
        broken) ln -s ../missing "$iocroot/tags/shared" ;;
        file) echo canary > "$iocroot/tags/shared" ;;
        *) ln -s "$old" "$iocroot/tags/shared" ;;
    esac
    case "$label" in writer|link) fault="$label" ;; esac
    before_pwd=$(pwd -P); status=0
    (
        __set_jail_prop tag=shared "$newid" "tank/iocell/jails/$newid"
        result=$?
        [ "$(pwd -P)" = "$before_pwd" ] || exit 99
        exit "$result"
    ) > "$workdir/$label.log" 2>&1 || status=$?
    case "$label" in
        writer|link|foreign|broken|file)
            want=1
            case "$label" in writer) want=6 ;; link) want=7 ;; esac
            if [ "$status" != "$want" ] || [ "$(cat "$new/config")" != tag=original ]; then
                echo "FAIL: tag $label changed config or ignored failure"; failed=1; continue
            fi
            [ "$(cat "$old/config")" = tag=shared ] || { failed=1; continue; }
            [ "$label" != foreign ] || [ "$(cat "$workdir/unmanaged/config")" = tag=untouched ] || exit 1
            [ "$label" != file ] || [ "$(cat "$iocroot/tags/shared")" = canary ] || exit 1
            [ ! -e "$iocroot/tags/2026-01-01@00:00:00" ] || {
                echo "FAIL: tag $label left a stray backup alias"; failed=1; continue;
            }
            ;;
        *)
            if [ "$status" != 0 ] || [ "$(cat "$new/config")" != tag=shared ] || \
                [ "$(cd "$iocroot/tags/shared" && pwd -P)" != "$(cd "$new" && pwd -P)" ]; then
                echo "FAIL: tag $label link and config disagree"; failed=1; continue
            fi
            oldtag=$(awk -F= '{print $2}' "$old/config")
            [ "$oldtag" != shared ] && [ -L "$iocroot/tags/$oldtag" ] && \
                [ "$(cd "$iocroot/tags/$oldtag" && pwd -P)" = "$(cd "$old" && pwd -P)" ] || {
                echo "FAIL: tag $label lost the old jail's alias"; failed=1; continue;
            }
            ;;
    esac
    [ "$(pwd -P)" = "$before_pwd" ] || exit 1
    echo "PASS: tag replacement $label"
done
ln -s "$new" "$iocroot/tags/current"
__link_tag "tank/iocell/jails/$newid" current
[ "$(pwd -P)" = "$before_pwd" ]
echo 'PASS: tag already targeting the same jail leaves caller directory unchanged'
mkdir "$new-extra"
ln -s "$new-extra" "$iocroot/tags/other-prefix"
__unlink_tag "tank/iocell/jails/$newid" "$new"
[ ! -L "$iocroot/tags/current" ] && [ -L "$iocroot/tags/other-prefix" ]
echo 'PASS: unlink removes only aliases for the exact mountpoint'
exit "$failed"
