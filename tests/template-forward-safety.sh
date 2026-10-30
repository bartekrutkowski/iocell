#!/bin/sh
# Forward conversion and the real UCL writer, with file-backed ZFS boundaries.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-info
. ./lib/ioc-zfs
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-forward.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT
trap 'exit 1' HUP INT TERM
pool=tank
uuid=11111111-1111-1111-1111-111111111111
source="tank/iocell/jails/$uuid"
__validate_pname () { echo custom; }
__is_running () { [ "$fault" != running ] || echo 1; }
uclcmd () {
    # No command in this double is allowed to access host /config.
    input=''; output=''
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -f) input="$2"; shift 2 ;;
            -o) output="$2"; shift 2 ;;
            --) shift; break ;;
            *) shift ;;
        esac
    done
    case "$input" in "$workdir"/*) ;; *) return 6 ;; esac
    [ "$fault" != ucl ] || return 6
    [ -n "$output" ] || output="$input"
    awk -F= -v key="$1" -v val="$2" '$1 != key {print} END {print key "=" val}' \
        "$input" > "$workdir/ucl-result" || return
    command cp "$workdir/ucl-result" "$output"
}
__get_jail_prop () {
    mp="$iocroot/${3#tank/iocell/}"
    case "$1" in
        mountpoint) [ -d "$mp" ] || return 1; echo "$mp" ;;
        *) awk -F= -v key="$1" '$1 == key {print substr($0,length(key)+2)}' "$mp/config" ;;
    esac
}
zfs () {
    case "$1" in
        get)
            for a in "$@"; do ds="$a"; done
            mp="$iocroot/${ds#tank/iocell/}"
            case "$*" in
                *' creation '*) [ -d "$mp" ] ;;
                *' origin '*)
                    [ "$fault" != query ] || return 9
                    [ "$fault" != origin ] || return 8
                    printf '%s\t-\n' "$source/root" ;;
                *' jailed '*) cat "$mp/jailed" ;;
                *' mountpoint '*) [ -d "$mp" ] || return 1; echo "$mp" ;;
                *) return 1 ;;
            esac
            ;;
        set)
            mp="$iocroot/${3#tank/iocell/}"
            [ -d "$mp" ] || return 1
            echo "${2#jailed=}" > "$mp/jailed"
            ;;
        rename)
            [ "$fault" != rename ] || return 7
            from="$iocroot/${3#tank/iocell/}"; to="$iocroot/${4#tank/iocell/}"
            [ ! -e "$to" ] || return 7
            mv "$from" "$to"
            ;;
        *) return 1 ;;
    esac
}
failed=0
for label in normal delegated-off timestamp slash running collision rename query origin ; do
    iocroot="$workdir/$label"; fault=none; tag=forward-template; delegated=on
    case "$label" in
        delegated-off) delegated=off ;;
        timestamp) tag='2026-01-01@00:00:00' ;;
        slash) tag='other/template' ;;
        normal) ;;
        *) fault="$label" ;;
    esac
    parent="$iocroot/jails/$uuid"; target="$iocroot/templates/$tag"
    mkdir -p "$parent/root" "$parent/data" "$iocroot/templates" "$iocroot/tags"
    printf 'tag=%s\ntype=basejail\nistemplate=no\n' "$tag" > "$parent/config"
    cp "$parent/config" "$workdir/before"
    echo "$delegated" > "$parent/data/jailed"
    echo content > "$parent/root/marker"
    # Only ordinary filesystem-safe tags have an alias fixture.
    alias="$iocroot/tags/alias"
    ln -s "$parent" "$alias"
    if [ "$fault" = collision ]; then mkdir "$target"; echo occupied > "$target/canary"; fi
    status=0; error=''
    ( set +e; __set_jail_prop istemplate=yes "$uuid" "$source" ) > "$workdir/$label.log" 2>&1 || status=$?
    case "$label" in
        normal|delegated-off)
            if [ "$status" -ne 0 ] || [ -e "$parent" ] || [ ! -e "$target/root/marker" ] || \
                ! grep -qx 'type=template' "$target/config" || \
                ! grep -qx 'istemplate=yes' "$target/config" || \
                [ "$(cat "$target/data/jailed")" != "$delegated" ] || [ -L "$alias" ]; then
                echo "FAIL: $label conversion lost data/state or metadata"; failed=1; continue
            fi
            ;;
        *)
            if [ "$status" -eq 0 ] || [ ! -e "$parent/root/marker" ] || \
                ! cmp -s "$workdir/before" "$parent/config" || \
                [ "$(cat "$parent/data/jailed")" != "$delegated" ] || \
                [ "$(readlink "$alias")" != "$parent" ]; then
                echo "FAIL: $label conversion reports success or changes source"; failed=1; continue
            fi
            ;;
    esac
    echo "PASS: forward conversion $label"
done
# Malformed mountpoints and UCL failures must propagate, never become success.
fault=none
for mp in '' / none "$workdir/missing" ; do
    status=0
    ( set +e; __ucl_set "$mp" istemplate yes ) > "$workdir/writer.log" 2>&1 || status=$?
    if [ "$status" = 0 ]; then echo "FAIL: UCL accepts invalid mountpoint '$mp'"; failed=1
    else echo "PASS: UCL rejects invalid mountpoint '$mp'"; fi
done
mkdir -p "$workdir/writer"; echo sentinel > "$workdir/writer/config"
fault=ucl; status=0
( set +e; __ucl_set "$workdir/writer" istemplate yes ) > "$workdir/writer.log" 2>&1 || status=$?
if [ "$status" -eq 0 ] || [ "$(cat "$workdir/writer/config")" != sentinel ]; then
    echo 'FAIL: UCL failure reports success or changes config'; failed=1
else echo 'PASS: UCL failure preserves config and returns failure'; fi
exit "$failed"
