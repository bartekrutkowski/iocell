#!/bin/sh
# Actual Git plugin checkouts must track default release branches, not detach.
set -eu
cd "$(dirname "$0")/.."
. ./tests/native-common.sh
ioc_test_require_pool
. ./lib/ioc-common
. ./lib/ioc-git
workdir=$(mktemp -d /var/tmp/iocell-plugin-branch.XXXXXX)
echo "Retained plugin branch logs: $workdir"
export GIT_AUTHOR_NAME=iocell-test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=iocell-test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir "$workdir/owner" "$workdir/iocell"
git init -q --bare "$workdir/owner/repo"
ln -s ../owner/repo "$workdir/iocell/repo"
git init -q "$workdir/upstream"
echo baseline > "$workdir/upstream/data"
git -C "$workdir/upstream" add data
git -C "$workdir/upstream" commit -qm baseline
git -C "$workdir/upstream" branch -M 15.1-amd64
git -C "$workdir/upstream" remote add origin "$workdir/owner/repo"
git -C "$workdir/upstream" push -qu origin 15.1-amd64
__get_default_prop () { echo "$workdir"; }
__get_jail_prop () { echo "$mp"; }
__find_jail () { echo tank/iocell/jails/fixture; }
__check_name () { echo fixture; }
__create_jail () { uuid=11111111-1111-1111-1111-111111111111; mkdir -p "$mp/root"; }
__update () { return 0; }
uname () { echo 15.1-RELEASE; }
pool=tank; iocroot="$workdir/tree"
mkdir -p "$iocroot/releases/15.1-RELEASE/root"
echo complete > "$iocroot/releases/15.1-RELEASE/root/marker"
for owner in owner iocell; do
    mp="$workdir/$owner-jail"
    ( set +u; iocset_branch=''; iocset_release=15.1-RELEASE
        __fetch_plugin "$owner/repo"
    ) > "$workdir/$owner.fetch" 2>&1
    [ "$(git -C "$mp/root" symbolic-ref --short HEAD)" = 15.1-amd64 ]
    [ "$(git -C "$mp/root" rev-parse --abbrev-ref --symbolic-full-name '@{u}')" = origin/15.1-amd64 ]
    echo "$owner-updated" > "$workdir/upstream/data"
    git -C "$workdir/upstream" commit -qam "$owner-update"
    git -C "$workdir/upstream" push -q
    ( __pull fixture ) > "$workdir/$owner.pull" 2>&1
    [ "$(cat "$mp/root/data")" = "$owner-updated" ]
    echo "PASS: actual $owner plugin default checkout tracks and pulls its release branch"
done
