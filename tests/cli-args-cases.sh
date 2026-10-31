#!/bin/sh
# Shared syntax failures. The caller supplies reject() and a disposable target.
cli_invalid_cases () {
    reject unknown definitely-not-a-command
    reject global-option --not-an-option
    reject empty-command ''
    for cmd in cap clone console destroy exec export get import init-host pkg \
        promote pull push reboot restart reset rollback runtime set send \
        snaplist snapmount snapremove snapshot snap snapumount start stop \
        uncap update upgrade; do
        reject "missing-$cmd" "$cmd"
    done
    for cmd in destroy start; do
        reject "force-missing-$cmd" "$cmd" -f
        reject "bad-option-$cmd" "$cmd" -z "$target"
        reject "late-option-$cmd" "$cmd" "$target" -z
        reject "empty-target-$cmd" "$cmd" "$target" ''
    done
    for cmd in reboot restart; do
        reject "soft-missing-$cmd" "$cmd" -s
        reject "bad-option-$cmd" "$cmd" -z "$target"
        reject "late-option-$cmd" "$cmd" -s "$target" -z
    done
    reject stop-option stop "$target" -z
    reject console-force console -f
    reject console-option console -z "$target"
    reject get-target get notes
    reject get-recursive-property get -r
    reject get-option get -z "$target"
    reject get-recursive-option get -r -z
    reject get-extra get notes "$target" ignored
    reject set-property set "$target"
    reject set-default-property set default
    reject set-target set notes=changed
    reject set-option set notes=changed "$target" -z
    reject set-empty-value set notes=changed boot= "$target"
    reject set-unknown-property set notes=changed unknown_property=value "$target"
    reject clone-property clone "$target" -z
    reject clone-property-first clone tag=copy
    reject create-option create -z
    reject create-late-option create -e tag=guard -z
    reject create-bare-argument create -e not-a-property
    reject create-unknown-property create -e unknown_property=value
    reject clean-no-selection clean
    reject clean-force-only clean -f
    reject clean-option clean -z
    reject clean-late-option clean -a -z
    reject clean-extra clean -t ignored
    reject snapshot-recursive-target snapshot -r
    reject snapshot-force-recursive-target snapshot -f -r
    reject snapshot-extra snapshot "$target@guard" ignored
    reject snapmount-destination snapmount "$target@guard"
    for cmd in rollback snapremove snapumount; do
        reject "snapshot-component-$cmd" "$cmd" "$target"
    done
    reject snapmount-snapshot snapmount "$target" /tmp
    reject init-host-pool init-host private-peer
    reject update-switch-target update -p
    reject update-option update -z "$target"
    reject upgrade-option upgrade "$target" -z
    reject exec-user exec -u
    reject exec-target exec -u root
    reject exec-option exec -z "$target" true
    reject exec-user-conflict exec -u root -U root "$target" true
    reject pkg-target pkg
    reject pkg-command pkg "$target"
    reject fetch-option fetch -z
    reject fetch-late-option fetch release=15.1-RELEASE -z
    reject fetch-thick-repository fetch -t
    reject fetch-plugin-order fetch tag=plugin owner/repo
    reject fetch-plugin-ports fetch -p owner/repo
    reject list-option list -z
    reject list-extra list -r ignored
    reject list-sort-column list -s not-a-column
    reject help-extra help ignored
    reject defaults-extra defaults ignored
    reject send-option send -z destination
    reject send-extra send source destination
    reject send-option-argument send -h
    reject send-host-missing send -r -u root destination
    reject send-remote-flag send -h private-peer -u root destination
    reject send-move-remote send -m -r -h private-peer -u root destination
    reject send-short-increment send -r -h private-peer -u root \
        -i source/iocell@first destination
    reject send-mixed-increment send -i source/iocell@first \
        -I source/iocell@last destination
    reject send-clean-increment send -c -i source/iocell@first \
        -i source/iocell@last destination
    reject send-clean-missing-peer send -c -r destination
}
