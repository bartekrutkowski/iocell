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
zfs () {
    for last; do :; done
    case "$*" in *' mounted '*)
        case "$fault:$last" in unmounted:*"$newid"|old-unmounted:*"$oldid") echo no ;;
            *) echo yes ;; esac
        return 0 ;;
    esac
    [ "$fault:$last" != "unowned:tank/iocell/jails/$oldid" ] || return 1
    if [ "$fault" = bad-mount ]; then echo /; else echo "$iocroot/jails/${last##*/}"; fi
}
mktemp () {
    [ "$fault" != bad-mount ] || return 99
    command mktemp "$@"
}
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
    if [ "$fault" = source-writer ]; then
        [ "$input" != "$new/config" ] || return 6
    fi
    [ -n "$output" ] || output="$input"
    printf 'tag=%s\n' "$2" > "$output"
}
ln () {
    [ "$fault" != rollback ] || [ "$1" != -sfn ] || return 6
    [ "$fault" != link ] || [ "$1" != -sfn ] || return 7
    [ "$fault" != new-link ] || [ "$1" != -s ] || return 7
    command ln "$@"
}
aliases () {
    find "$iocroot/tags" -type l -exec sh -c '
        for path; do printf "%s=%s\n" "$path" "$(readlink "$path")"; done
    ' sh {} + | sort
}
mv () {
    for target; do :; done
    if [ "$fault" = rollback ] && [ "$1" = -f ] && [ "$target" = "$old_physical/config" ]; then
        return 44
    fi
    if [ "$fault" = after-write ] && [ "$target" = "$new/config" ] && \
        [ ! -e "$workdir/$label.injected" ]; then
        command mv "$@" || return $?
        touch "$workdir/$label.injected"; return 6
    fi
    command mv "$@"
}
mkdir "$workdir/bin"
for tool in rm mv; do
    printf '%s\n' '#!/bin/sh' 'tool=${0##*/}; source=$1' \
        'if [ "$tool" = rm ]; then for source; do :; done; fi' \
        'if [ "$tool" = rm ] && [ "${IOC_TAG_FAIL_BACKUP:-}" = yes ]; then' \
        '    case "$source" in */.iocell-alias.*/*) exit 42 ;; esac' 'fi' \
        'if [ "$source" = "${IOC_TAG_FAIL_ALIAS:-}" ]; then' \
        '    "/bin/$tool" "$@" || exit $?; exit 42' 'fi' \
        'exec "/bin/$tool" "$@"' > "$workdir/bin/$tool"
    chmod +x "$workdir/bin/$tool"
done
PATH="$workdir/bin:$PATH"; export PATH
failed=0
for label in absolute relative path-glob relative-glob collision same literal writer source-writer \
    collision-source-writer same-writer after-write link new-link foreign broken broken-writer file bad-mount unowned unmounted old-unmounted mismatch cleanup backup-cleanup; do
    iocroot="$workdir/$label/iocell"; altroot=-; fault=none; requested=shared
    case "$label" in *-glob) iocroot="$workdir/$label[ab]/iocell" ;; esac
    old="$iocroot/jails/$oldid"; new="$iocroot/jails/$newid"
    mkdir -p "$old" "$new" "$iocroot/tags"
    echo tag=shared > "$old/config"; echo tag=original > "$new/config"
    cp "$new/config" "$workdir/$label.before"
    [ "$label" != mismatch ] || echo tag=different > "$old/config"
    cp "$old/config" "$workdir/$label.old-before"
    IOC_TAG_FAIL_ALIAS=''; IOC_TAG_FAIL_BACKUP=''
    export IOC_TAG_FAIL_ALIAS IOC_TAG_FAIL_BACKUP
    [ "$label" != cleanup ] || IOC_TAG_FAIL_ALIAS="$iocroot/tags/original"
    [ "$label" != backup-cleanup ] || IOC_TAG_FAIL_BACKUP=yes
    ln -s "$new" "$iocroot/tags/original"
    ln -s "../jails/$newid" "$iocroot/tags/other-original"
    case "$label" in
        same|same-writer) requested=original ;;
        literal) requested='new[1]*?' ;;
        source-writer|new-link) : ;;
        relative|relative-glob) altroot="$workdir/$label"; ln -s "../jails/$oldid" "$iocroot/tags/shared" ;;
        collision)
            ln -s "$old" "$iocroot/tags/shared"
            ln -s "$old" "$iocroot/tags/2026-01-01@00:00:00" ;;
        foreign)
            mkdir "$workdir/unmanaged"; echo tag=untouched > "$workdir/unmanaged/config"
            ln -s "$workdir/unmanaged" "$iocroot/tags/shared" ;;
        broken|broken-writer) ln -s ../missing "$iocroot/tags/shared" ;;
        file) echo canary > "$iocroot/tags/shared" ;;
        *) ln -s "$old" "$iocroot/tags/shared" ;;
    esac
    aliases > "$workdir/$label.aliases-before"
    case "$label" in
        writer|source-writer|link|new-link) fault="$label" ;;
        collision-source-writer|same-writer|broken-writer) fault=source-writer ;;
        after-write) fault=after-write ;;
        bad-mount|unowned|unmounted|old-unmounted) fault="$label" ;;
    esac
    before_pwd=$(pwd -P); status=0
    (
        __set_jail_prop "tag=$requested" "$newid" "tank/iocell/jails/$newid"
        result=$?
        [ "$(pwd -P)" = "$before_pwd" ] || exit 99
        exit "$result"
    ) > "$workdir/$label.log" 2>&1 || status=$?
    case "$label" in
        backup-cleanup)
            if [ "$status" != 1 ] || [ "$(cat "$new/config")" != tag=shared ] ||
                [ "$(readlink "$iocroot/tags/shared")" != "$new" ] ||
                [ -L "$iocroot/tags/original" ] ||
                ! grep -q 'retag committed' "$workdir/$label.log"; then
                echo 'FAIL: committed retag cleanup failure hid its actual state'; failed=1; continue
            fi
            backup=$(find "$iocroot" -type d -name '.iocell-alias.*')
            if [ -z "$backup" ] || [ ! -L "$backup/original" ]; then
                echo 'FAIL: committed retag discarded failed alias cleanup data'; failed=1; continue
            fi
            ;;
        writer|source-writer|collision-source-writer|same-writer|after-write|link|new-link|foreign|broken-writer|file|bad-mount|unowned|unmounted|old-unmounted|mismatch|cleanup)
            want=1
            case "$label" in writer|source-writer|collision-source-writer|same-writer|after-write|broken-writer) want=6 ;;
                link|new-link) want=7 ;; esac
            if [ "$status" != "$want" ] || \
                ! cmp -s "$new/config" "$workdir/$label.before" || \
                [ "$(readlink "$iocroot/tags/original")" != "$new" ] || \
                [ "$(readlink "$iocroot/tags/other-original")" != "../jails/$newid" ]; then
                echo "FAIL: tag $label lost previous aliases/config or ignored failure"
                failed=1; continue
            fi
            aliases > "$workdir/$label.aliases-after"
            if ! cmp -s "$workdir/$label.aliases-before" "$workdir/$label.aliases-after" || \
                ! cmp -s "$old/config" "$workdir/$label.old-before"; then
                echo "FAIL: tag $label left partial namespace or displaced metadata"
                failed=1; continue
            fi
            [ "$label" != foreign ] || [ "$(cat "$workdir/unmanaged/config")" = tag=untouched ] || exit 1
            [ "$label" != file ] || [ "$(cat "$iocroot/tags/shared")" = canary ] || exit 1
            [ ! -e "$iocroot/tags/2026-01-01@00:00:00" ] || {
                echo "FAIL: tag $label left a stray backup alias"; failed=1; continue;
            }
            ;;
        *)
            if [ "$status" != 0 ] || [ "$(cat "$new/config")" != "tag=$requested" ] || \
                [ "$(cd "$iocroot/tags/$requested" && pwd -P)" != "$(cd "$new" && pwd -P)" ]; then
                echo "FAIL: tag $label link and config disagree"; failed=1; continue
            fi
            [ ! -L "$iocroot/tags/other-original" ] || {
                echo "FAIL: tag $label retained an obsolete relative alias"; failed=1; continue;
            }
            if [ "$requested" != original ] && [ -L "$iocroot/tags/original" ]; then
                echo "FAIL: tag $label retained an obsolete absolute alias"; failed=1; continue
            fi
            case "$label" in same|literal|broken) : ;; *)
                oldtag=$(awk -F= '{print $2}' "$old/config")
                [ "$oldtag" != shared ] && [ -L "$iocroot/tags/$oldtag" ] && \
                    [ "$(cd "$iocroot/tags/$oldtag" && pwd -P)" = "$(cd "$old" && pwd -P)" ] || {
                    echo "FAIL: tag $label lost the old jail's alias"; failed=1; continue;
                } ;;
            esac
            ;;
    esac
    [ "$(pwd -P)" = "$before_pwd" ] || exit 1
    if [ -n "$(find "$iocroot/jails" -name '.iocell-tag.*' -print)" ]; then
        echo "FAIL: tag $label left temporary recovery files"; failed=1; continue
    fi
    if [ "$label" != backup-cleanup ] &&
        [ -n "$(find "$iocroot" -type d -name '.iocell-alias.*')" ]; then
        echo "FAIL: tag $label accumulated private alias backups"; failed=1; continue
    fi
    echo "PASS: tag replacement $label"
done
fault=none; IOC_TAG_FAIL_ALIAS=''; IOC_TAG_FAIL_BACKUP=''
ln -s "$new" "$iocroot/tags/current"
__link_tag "tank/iocell/jails/$newid" current
[ "$(pwd -P)" = "$before_pwd" ]
echo 'PASS: tag already targeting the same jail leaves caller directory unchanged'
mkdir "$new-extra"
ln -s "$new-extra" "$iocroot/tags/other-prefix"
__unlink_tag "tank/iocell/jails/$newid" "$new"
[ ! -L "$iocroot/tags/current" ] && [ -L "$iocroot/tags/other-prefix" ]
echo 'PASS: unlink removes only aliases for the exact mountpoint'
iocroot="$workdir/recovery"; old="$iocroot/jails/$oldid"; new="$iocroot/jails/$newid"
mkdir -p "$old" "$new" "$iocroot/tags"
old_physical=$(cd "$old" && pwd -P)
echo tag=shared > "$old/config"; echo tag=original > "$new/config"
ln -s "$new" "$iocroot/tags/original"; ln -s "$old" "$iocroot/tags/shared"
fault=rollback; status=0
( __set_jail_prop tag=shared "$newid" "tank/iocell/jails/$newid" ) \
    > "$workdir/recovery.log" 2>&1 || status=$?
backup="$old/config.old"
if [ "$status" != 6 ] || ! grep -q 'rollback incomplete' "$workdir/recovery.log" || \
    [ ! -f "$backup" ] || [ "$(cat "$backup")" != tag=shared ] || \
    [ "$(cat "$new/config")" != tag=original ] || \
    [ "$(readlink "$iocroot/tags/original")" != "$new" ]; then
    echo 'FAIL: failed rollback discarded recovery data or hid the original error'; failed=1
else echo 'PASS: failed rollback retains original config backup and reports its path'; fi
fault=none
iocroot="$workdir/path[ab]"; exact="$iocroot/jails/$newid"
neighbor="$workdir/patha/jails/$newid"
mkdir -p "$exact" "$neighbor" "$iocroot/tags"
ln -s "$exact" "$iocroot/tags/exact"
ln -s "$neighbor" "$iocroot/tags/unrelated"
__unlink_tag "tank/iocell/jails/$newid" "$exact"
if [ -L "$iocroot/tags/exact" ] || [ ! -L "$iocroot/tags/unrelated" ]; then
    echo 'FAIL: unlink interpreted the mountpoint as a glob'; failed=1
else echo 'PASS: unlink compares target paths literally'; fi
exit "$failed"
