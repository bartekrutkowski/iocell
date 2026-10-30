#!/bin/sh
# Exercise real dispatch/preflight; handler boundaries cannot mutate the host.
set -e
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-cmd
. ./tests/cli-dispatch.sh
. ./lib/ioc-help
. ./lib/ioc-zfs
. ./tests/cli-args-cases.sh
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-cli-args.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
trap 'exit 1' HUP INT TERM
target=example; pool=source; tag=example; PAGER=cat
CONF_NET=vnet; CONF_JAIL=login_flags; CONF_RCTL=''; CONF_CUSTOM='notes tag boot'
CONF_SYNC=''; CONF_FTP=release; CONF_GIT='gitlocation branch'; CONF_ZFS=''
# Keep send's real implementation for a second, direct-call guard test.
# Dispatch itself only owns the hand-off to command handlers.
for handler in __activate __rctl_limits __clean __clone_jail __console \
    __create_jail __deactivate __print_defaults __destroy_jail __print_disk \
    __exec __export __fetch_release __get_jail_prop __init_host __rctl_inuse \
    __import __rctl_list __list_jails __promote __pull __push __rc_jails \
    __restart_jail __reboot_jail __reset_jail_props __rollback __runtime \
    __set_jail_prop __snaplist __mount_snapshot __umount_snapshot __snapremove \
    __snapshot __start_jail __stop_jail __rctl_uncap __update __upgrade \
    __pkg_wrapper; do
    eval "$handler () { printf '%s\\n' '$handler' \"\$@\" >> \"\$trace\"; }"
done
__find_jail () { echo "source/iocell/jails/$target"; }
__check_name () { echo "$target"; }
zfs () { echo "zfs $*" >> "$trace"; return 42; }
jls () { echo jls >> "$trace"; return 42; }
ssh () { echo ssh >> "$trace"; return 42; }
failed=0
reject () {
    label=$1; shift
    trace="$workdir/$label.trace"; : > "$trace"
    status=0
    ( set +e; ioc_test_dispatch "$@" ) > "$workdir/$label.log" 2>&1 || status=$?
    if [ "$status" = 0 ] || [ -s "$trace" ] || \
        [ ! -s "$workdir/$label.log" ]; then
        echo "FAIL: $label: status=$status; invalid arguments reached a handler"
        cat "$trace" "$workdir/$label.log"
        failed=1
    else
        echo "PASS: CLI rejects $label before dispatch"
    fi
}
cli_invalid_cases

# These inputs bypass dispatch in internal callers; send must still preflight.
for label in send-empty-direct send-clean-direct; do
    trace="$workdir/$label.trace"; : > "$trace"; status=0
    case "$label" in
        send-empty-direct) set -- ;;
        send-clean-direct) set -- -c -r destination ;;
    esac
    ( set +e; __send "$@" ) > "$workdir/$label.log" 2>&1 || status=$?
    if [ "$status" = 0 ] || [ -s "$trace" ]; then
        echo "FAIL: $label reached ZFS/SSH before rejection"
        cat "$trace" "$workdir/$label.log"; failed=1
    else
        echo "PASS: CLI rejects $label before system operations"
    fi
done

# Literal expected arguments catch validation consuming/reordering flags/data.
valid () {
    label=$1; expected=$2; shift 2
    trace="$workdir/$label.trace"; : > "$trace"; status=0
    ( set +e; ioc_test_dispatch "$@" ) > "$workdir/$label.log" 2>&1 || status=$?
    printf '%s\n' "$expected" > "$workdir/$label.expected"
    if [ "$status" != 0 ] || ! cmp -s "$trace" "$workdir/$label.expected"; then
        echo "FAIL: valid $label: status=$status"
        cat "$trace" "$workdir/$label.log"; failed=1
    else
        echo "PASS: CLI preserves $label"
    fi
}
valid forced-start '__start_jail
example' start -f example
valid multi-start '__start_jail
first
__start_jail
second' start first second
valid soft-restart '__restart_jail
example' restart -s example
valid hard-reboot '__reboot_jail
example' reboot example
valid recursive-get '__get_jail_prop
-r
notes' get -r notes
valid optional-limits '__rctl_list
' limits
valid list-sort-default '__list_jails
-s
' list -s
valid recursive-snapshot '__snapshot
-r
example@guard' snapshot -f -r example@guard
valid exec-payload '__exec
-u
root
example
/bin/sh
-c
printf "%s" "two words"' exec -u root example /bin/sh -c 'printf "%s" "two words"'
valid package-payload '__pkg_wrapper
pkg
example
query
%n %v' pkg example query '%n %v'
valid set-pairs '__set_jail_prop
notes=changed
example
__set_jail_prop
boot=on
example' set notes=changed boot=on example
valid default-trailing-equals '__set_jail_prop
notes=tail=
default' set notes=tail= default

# Positive forms whose actual handlers need a FreeBSD host or remote peer.
accept () {
    label=$1; shift
    trace="$workdir/grammar-$label.trace"; : > "$trace"; status=0
    ( __validate_cmd "$@" ) > "$workdir/grammar-$label.log" 2>&1 || status=$?
    if [ "$status" != 0 ] || [ -s "$trace" ]; then
        echo "FAIL: grammar $label is rejected or has side effects"
        cat "$workdir/grammar-$label.log" "$trace"; failed=1
    else
        echo "PASS: CLI accepts $label without side effects"
    fi
}
accept no-command
accept help-alias --help
accept short-help -h
accept version --version
accept active-pool-query activate
accept force-clean clean -tf
accept combined-clean clean -rj
accept clean-no-selection clean
accept list-templates list -t
accept list-releases list -r
accept list-warden list --warden
accept sort-case list -s UUID
accept sort-empty list -s ''
accept optional-inuse inuse
accept empty-create-value create -e login_flags=
accept clone-properties clone example@saved tag=copy
accept import-properties import image notes=restored
accept upgrade-properties upgrade example release=15.1-RELEASE
accept git-update update -n example
accept fetch-interactive fetch
accept fetch-ports fetch -p release=15.1-RELEASE
accept fetch-plugin fetch owner/repo gitlocation=/local/plugins release=15.1-RELEASE
accept fetch-thick-plugin fetch -t owner/repo
accept exec-optional-shell exec example
accept exec-option-separator exec -- example /bin/sh -c 'exit 17'
accept exec-payload-options exec example /bin/sh -z
accept send-local send destination
accept send-clean send -c destination
accept send-move send -m destination
accept send-remote send -r -h private-peer -u root destination
accept send-increment send -i first -i source/iocell@last destination
accept send-inclusive send -I source/iocell@first -I source/iocell@last destination
accept send-option-separator send -- destination
accept rollback-snapshot rollback example@saved
accept remove-all-snapshots snapremove example@ALL
accept mount-snapshot snapmount example@saved /tmp
accept unmount-snapshot snapumount example@saved
# A valid property preflight must run once, not again after initialization.
# Instrument only this final known-valid CLI syntax check, not the independent
# backend property validation. Real validation/malformed requests ran above.
validation_trace="$workdir/validation-count"; : > "$validation_trace"
trace="$workdir/once.trace"; : > "$trace"
__cli_properties () { printf '%s\n' "$@" >> "$validation_trace"; }
( ioc_test_dispatch set notes=once "$target" ) > "$workdir/once.log" 2>&1
if [ "$(wc -l < "$validation_trace" | tr -d ' ')" != 1 ]; then
    echo 'FAIL: dispatcher repeated the public syntax preflight'; failed=1
else echo 'PASS: public syntax preflight runs only once'; fi
exit "$failed"
