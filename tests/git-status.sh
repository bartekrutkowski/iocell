#!/bin/sh
# Real local Git repositories: failed fetch/merge must not claim pull success.
set -eu
cd "$(dirname "$0")/.."
. ./lib/ioc-common
. ./lib/ioc-git
workdir=$(mktemp -d "${TMPDIR:-/tmp}/iocell-git-status.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
export GIT_AUTHOR_NAME=iocell-test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=iocell-test GIT_COMMITTER_EMAIL=test@example.invalid
git init -q --bare "$workdir/origin"
git init -q "$workdir/upstream"
printf 'baseline\n' > "$workdir/upstream/data"
git -C "$workdir/upstream" add data
git -C "$workdir/upstream" commit -qm baseline
git -C "$workdir/upstream" branch -M main
git -C "$workdir/upstream" remote add origin "$workdir/origin"
git -C "$workdir/upstream" push -qu origin main
git --git-dir="$workdir/origin" symbolic-ref HEAD refs/heads/main
__find_jail () { echo tank/iocell/jails/fixture; }
__check_name () { echo fixture; }
__get_jail_prop () {
    case "$1" in mountpoint) echo "$mp" ;;
        type) [ "$mode" != n-notgit ] && echo gitjail || echo basejail ;; esac
}
__update () { echo update > "$mp/updated"; return "$update_status"; }
failed=0
for mode in fetch merge update success; do
    mp="$workdir/$mode"; mkdir "$mp"
    git clone -q "$workdir/origin" "$mp/root"
    git -C "$mp/root" rev-parse HEAD > "$mp/before"
    update_status=0; want=0
    case "$mode" in
        fetch) git -C "$mp/root" remote set-url origin "$mp/missing"; want=128 ;;
        merge)
            echo local > "$mp/root/local"
            git -C "$mp/root" add local; git -C "$mp/root" commit -qm local
            git -C "$mp/root" rev-parse HEAD > "$mp/before"
            echo remote > "$workdir/upstream/remote"
            git -C "$workdir/upstream" add remote
            git -C "$workdir/upstream" commit -qm remote
            git -C "$workdir/upstream" push -q; want=128 ;;
        update) update_status=43; want=43 ;;
    esac
    status=0
    ( __pull fixture ) > "$mp/result.log" 2>&1 || status=$?
    git -C "$mp/root" rev-parse HEAD > "$mp/after"
    if [ "$status" != "$want" ]; then
        echo "FAIL: pull $mode status=$status expected=$want"; failed=1
    elif [ "$mode" = fetch ] || [ "$mode" = merge ]; then
        if [ -e "$mp/updated" ] || ! cmp -s "$mp/before" "$mp/after"; then
            echo "FAIL: pull $mode mutated checkout or ran later update"; failed=1
        else echo "PASS: pull $mode failure stops later work and preserves checkout"; fi
    elif [ ! -e "$mp/updated" ]; then
        echo "FAIL: pull $mode skipped the successful merge continuation"; failed=1
    else echo "PASS: pull $mode preserves continuation status"; fi
done
# Exercise the real read-only update path as well as pull's OS continuation.
. ./lib/ioc-upgrade
mp="$workdir/success"
git -C "$mp/root" rev-parse HEAD > "$workdir/n.before"
for mode in n-success n-error n-notgit; do
    want=0; status=0
    case "$mode" in
        n-error) git -C "$mp/root" remote set-url origin "$mp/missing"; want=1 ;;
        n-notgit) want=1 ;;
    esac
    ( __update -n fixture ) > "$workdir/$mode.log" 2>&1 || status=$?
    git -C "$mp/root" rev-parse HEAD > "$workdir/n.after"
    if [ "$status" != "$want" ] || ! cmp -s "$workdir/n.before" "$workdir/n.after"; then
        echo "FAIL: update -n $mode lost status or changed checkout"; failed=1
    else echo "PASS: update -n $mode preserves status and checkout"; fi
done
exit "$failed"
