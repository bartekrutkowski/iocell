# Tests

Run the portable regression tests from the repository root:

```sh
sh tests/clone-snapshot.sh
sh tests/configure-failures.sh
sh tests/rollback.sh
sh tests/pkg-install.sh
sh tests/plugin-release.sh
sh tests/create-pkg.sh
sh tests/template-toggle.sh
sh tests/send-safety.sh
sh tests/send-args.sh
sh tests/send-cleanup.sh
sh tests/send-csh.sh
sh tests/discovery-safety.sh
sh tests/discovery-callers.sh
sh tests/autoip-discovery.sh
sh tests/bulk-jails.sh
sh tests/start-dispatch.sh
sh tests/start-failures.sh
sh tests/rc-jails.sh
sh tests/template-forward-safety.sh
sh tests/clean-template-safety.sh
sh tests/clean-dispatch.sh
sh tests/dependent-clones.sh
sh tests/migrate-safety.sh
sh tests/migrate-callers.sh
sh tests/tag-links.sh
sh tests/destroy-guard-safety.sh
sh tests/destroy-status.sh
sh tests/import.sh
sh tests/defaults.sh
sh tests/cli-args.sh
sh tests/native-test-guard.sh
sh tests/set-values.sh
sh tests/console-force.sh
sh tests/version.sh
```

These execute the real shell functions with mocked ZFS/system calls. They do
not require FreeBSD, root, or a ZFS pool. The defaults test needs Python 3 for
its external UCL boundary double. It covers persistence, creation inheritance,
explicit overrides, literal none/null values, fresh identities, invalid input,
and parser/write/rename failures without touching existing jails.
The import test covers successful
full/prefix selection, corrupt/truncated receives, preserved diagnostics and
partial data, existing targets, missing images and ambiguous selection.
The clone test covers explicit and automatic root/data snapshots, missing
snapshots, source/list/snapshot failures, failed root/data clones and failed
configuration/alias publication. It verifies saved versus live bytes. The rollback
test covers target selection, snapshot preflight, running jails, and error
propagation. Package tests cover list parsing, first-error propagation, release
and template selection, partial mount failures, cleanup, and cleanup failures.
Child stdin is isolated from the package list. Failure coverage includes each
template release/lower, template overlay and writable jail overlay mount.
Template tests cover stored UUID selection, delegated state, validation, clone
and running-jail guards, rename errors, and propagation through the CLI.
Send tests check literal snapshot operands and validation-state isolation.
The csh test
executes plain/buffered receiver commands, checks transferred bytes and both
failure statuses, and verifies temporary-directory cleanup; it is not syntax-only.
Safety tests additionally cover fresh full-send snapshots, every pipeline stage
(including both buffers), activation failures, source identity across moves,
read-only discovery, legacy-config preservation, forward conversion failures,
invalid config paths, cleanup races and propagation of dependency-query errors.

## Authorization for every native test

Use a disposable FreeBSD host and an activated, dedicated test pool. Before
running any `*-zfs.sh` script, explicitly authorize that pool and each run:

```sh
export IOC_TEST_POOL=YOUR_DISPOSABLE_POOL
zfs set org.freebsd.iocell:test=yes "$IOC_TEST_POOL"
export IOC_TEST_DESTRUCTIVE=yes
```

Do not set this marker on a production pool. A test-looking pool name is not
a safety check. The shared guard verifies the local marker, FreeBSD/root,
the dataset actually mounted at iocell's configured root, and the pool selector
without invoking iocell's filesystem initialization. Failed preconditions print
a diagnostic and stop before fixtures or host configuration are changed.

Scratch pool names use UUIDs rather than PIDs. Native tests retain their logs,
file vdevs and fixtures; their printed paths identify what they leave behind.

## Destroy failure boundaries

`destroy-status.sh` checks returned/exiting dispatcher failures and the real
backend's query/ZFS error boundaries. Failure must stop later targets and retain
aliases and data; leftover host-side files are not recursively erased.
Authorized `destroy-status-zfs.sh` verifies these boundaries with real kernel
jails, datasets, config bytes, aliases and canaries. A successful deletion must
also return zero when no legacy base dataset exists.

## Configuration generation failures

`configure-failures.sh` checks first-error propagation through real generation
and reset helpers, including native-property errors. With native authorization,
`configure-failures-zfs.sh` injects a real UCL write failure through CLI create
and clone. Neither command may publish success or create a tag alias; partial
datasets remain inspectable. Source config/data/GUIDs and activation are checked.

`create-altroot-zfs.sh` runs real create/clone backends in an owned altroot
pool. It verifies canonical dataset selection, native compression, config UUIDs,
relative aliases and source preservation. It selects the backend pool/root
explicitly; the separate CLI bootstrap issue with a simultaneous `/iocell` is
not hidden by this test.

## Migration failure boundaries

`migrate-callers.sh` tests the real layout checker and start/update/upgrade
callers. Returned and exiting failures must preserve their status and stop
later work, including upgrade backout. `template-toggle.sh` also checks that
reverse conversion does not finalize its flag after a failed layout check.

With native authorization set, run:

```sh
IOC_TEST_RELEASE=15.1-RELEASE sh tests/migrate-callers-zfs.sh
```

This uses real ZFS legacy-layout fixtures, UCL and the migration preflight.
OS update, Git/network and kernel-operation boundaries are inert; this is not
an actual OS upgrade or plugin installation. Git must be installed for plugin
caller fixtures. Failed start/update/upgrade and both plugin release paths
must stop at the same rejection without changing config, canaries or GUIDs.
Plugin success controls and release-fetch spinner cleanup are also checked.

`plugin-release.sh` and authorized `plugin-release-zfs.sh` exercise failed-fetch
cleanup. Only a mounted, empty release parent/root pair can be removed, using
nonrecursive dataset destroys. Snapshots, additional datasets, parent data and
unmounted roots cause refusal without removing protected state. Plugin caller
tests also inject release-property failures and check that spinner diagnostics
start on their own line after the spinner is stopped.

## rc boot and shutdown selection

`rc-jails.sh` keeps discovery, property reads and rc selection real. It checks
boot/hostid filtering, priority order, reverse shutdown order and propagation
of discovery failures before any lifecycle action.

With native authorization set as above, run `sh tests/rc-jails-zfs.sh`. It uses
an owned scratch pool with real ZFS/UCL metadata and minimal kernel persist
jails. It exercises rc selection and kernel creation/removal, not full jail
userland startup. Config bytes, canaries, dataset GUIDs and activation must
remain unchanged. Only that test's jails are stopped; pool and logs are retained.

`clean-dispatch.sh` keeps validation, dispatch and cleanup scanning real.
Separate and clustered cleanup flags retain order and the shared force setting;
empty/force-only calls fail, and handler errors stop subsequent cleanup modes.
`-a` subsumes other modes and runs only once. The authorized `clean-all-zfs.sh`
checks actual combined-mode wipes and preserves data/GUIDs on stop or storage
failure. Cleanup spinners must return the command's status and reap their child.

## CLI syntax and native entrypoint tests

`cli-args.sh` exercises the real preflight and dispatcher with inert command
handler boundaries, plus direct send preflight. The public entrypoint validates
before initialization; private dispatch does not repeat that whole pass.
`tests/cli-dispatch.sh` mirrors this flow for unit callers, and a counter regression
distinguishes CLI syntax checks from independent backend property validation.
Send tests preserve individual incremental operands and reject failed running-jail
queries before any move snapshot/transfer. Shared failure cases live in
`cli-args-cases.sh`. Unknown commands/options, missing/empty operands, bad list
sort columns, malformed property syntax, late flags and malformed send options
must fail before a handler/system operation. Positive cases preserve argument
order, optional arguments, legacy accepted forms and exec/pkg payloads.

On the disposable FreeBSD host, use a fetched release and the activated test
pool; normal iocell dependencies and root are required:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_RELEASE=15.1-RELEASE \
    sh tests/cli-args-zfs.sh
```

This tests the actual entrypoint. Guard wrappers fail if rejected commands
reach ZFS, UCL, jail, mount, RCTL, SSH or file-mutating utility handling;
initial read-only platform checks remain real. Config/default bytes, a data canary, dataset GUIDs and the
filesystem/snapshot namespace must stay unchanged. Real successful commands
exercise help/version aliases, verbose forms, reads, recursive snapshots,
start/stop, hard/soft restart, exec quoting/status, and deletion of only a second
new, uniquely identified fixture. The primary fixture and logs are retained;
cleanup stops its jail if a test fails. Existing jails/datasets are not deleted.

This is CLI syntax coverage, not full property/kernel validation or a promise
of atomic multi-target commands. Real SSH/send data-path tests are below.

## Multi-target startup

`start-dispatch.sh` checks ordered attempts, force propagation and the first
failure status for returned and exiting backends. `start-failures.sh` keeps the
real startup phases and checks that failures return to callers, stop later
work, and select the correct mount cleanup without masking the original error.

With native authorization and a fetched release, `start-multi-zfs.sh` starts a
real valid jail after earlier targets fail. It checks first-error preservation,
actual kernel state, unchanged failed-jail configs/data/GUIDs, and stops its own
jails on exit. Fixtures and logs are retained.

## Forced console startup

`console-force.sh` checks the resolved identity, no redundant start for a
running jail, and no login after a failed start.

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_RELEASE=15.1-RELEASE \
    sh tests/console-force-zfs.sh
```

The native fixture starts through the real `console -f` path. Only interactive
login is replaced; the wrapper requires that its kernel jail actually exists.
A second console invocation must retain the same jail ID. Stopped templates
must not be started by `console -f`. Cleanup stops the fixture and retains its
datasets and logs. `mount-diagnostics-zfs.sh` checks real nullfs errors: legacy
best-effort mode stays quiet and continues; strict package setup reports the
error and stops before later mounts.

## Literal property-value tests

`set-values.sh` exercises the real dispatcher and property setter with a
configuration writer boundary: equals signs, apostrophes, repeated spaces,
newlines and literal shell text must reach storage unchanged. It also tests
the reserved-tag command predicate and malformed direct setter calls.

```sh
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/set-values-zfs.sh
```

The native counterpart uses new empty-jail fixtures and real UCL storage. A
write failure must stop later properties and later jails; earlier successful
properties remain applied, so the test does not imply batch transactions.

## Real-ZFS discovery and bulk lifecycle test

With the authorization above and a fetched release:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_RELEASE=15.1-RELEASE \
    sh tests/discovery-zfs.sh
```

It verifies actual legacy migration preserves native quota/compression, string
values and data; a failed UCL write publishes no partial config and can be
retried. Unconfigured identities remain visible without invented metadata.
A new unconfigured kernel jail and a real basejail exercise `stop ALL`: the
former is reported/skipped, the later valid jail stops, and the command returns
failure. Cleanup stops the kernel jail and removes GUID-verified incomplete
fixtures after success; failed fixtures, valid jails, and logs are retained.
`lookup-case-zfs.sh` checks UUID/template-name case folding, literal config tags,
and ambiguous names without changing configuration bytes or dataset GUIDs.
Portable bulk tests cover start/stop/reboot/restart continuation and enumeration
failures without relying on pipelines that can hide discovery status.
`discovery-callers.sh` also checks list/warden, resource reporting, auto-IP,
reset, show/disk and upgrade consumers with partial output followed by failure.
`discovery-callers-zfs.sh` injects a native enumeration error through those real
callers and verifies unchanged configuration, data and dataset GUIDs.
`autoip-discovery.sh` checks both network modes and their startup callers, plus
selection of an unused address when another jail already owns the first one.

## Real-ZFS clone integration test

With the authorization above:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/clone-zfs.sh
```

This retains a source and clone fixtures. It checks historical and automatic
root/delegated-data bytes, original snapshot GUIDs, and absent root/data snapshot
rejection before destination creation. Injected real clone failures return
nonzero without publishing config or a tag alias. Partial datasets are retained
for inspection. An existing data dataset with no matching historical snapshot
is an error, not a request to silently replace its contents with empty data.

## Real-ZFS defaults integration test

On a disposable FreeBSD VM, stop all jails and opt in using the activated test
pool. Root, real `uclcmd`, ZFS and normal iocell dependencies are required:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/defaults-zfs.sh
```

This creates a uniquely named 512 MiB file-backed pool, temporarily activates it
and restores the original activation on exit. Logs, vdev, pool and fixtures are
retained. No release download or jail startup is needed. Independent CLI
invocations verify persistence/display, inherited and overridden properties,
fresh UUIDs/hostnames, native compression, creation-count defaults, literal
none/zero/null values, default-file permissions and rejection/error propagation.
Existing config bytes, data, GUIDs and active-pool identity are checked. The
native UCL parser and an injected writer failure both leave originals intact.
This does not qualify arbitrary property combinations or reset-to-saved-defaults.

## Real-ZFS import integration test

On the disposable FreeBSD host, use an activated test pool and a fetched release:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_RELEASE=15.1-RELEASE \
    sh tests/import-zfs.sh
```

This creates a filesystem-only fixture with real config, random data and a
recursive snapshot/stream. It verifies valid full/short image imports, native
corrupt/truncated stream rejection, diagnostic/exit propagation, original image
integrity, and protection of existing full/prefix-selected targets. A receive
that completes writing data and then reports failure must return that failure
without destroying the received data. Contents, exact config bytes, filesystem
and snapshot GUIDs are checked as appropriate.

Only this run's fixture is explicitly reset between cases, after recording any
partial receive state. The importer itself must not automatically destroy a
partial target. Logs, input images and the final restored jail are retained.
Legacy thick-jail archive error handling is not covered by this stream fix.

## Real-ZFS rollback integration test

Use **only a disposable FreeBSD VM with a dedicated, activated test pool**.
Requires root, `uclcmd`, and the normal iocell dependencies. This test creates
filesystem-only jail fixtures; it does not fetch or boot a FreeBSD jail image.
It briefly creates a network-disabled persistent jail to test running-jail
protection, then removes that jail instance. Datasets and snapshots are kept.

Activate your test pool first, then explicitly opt in:

```sh
sh ./iocell activate YOUR_TEST_POOL
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/rollback-zfs.sh
```

The test refuses to run if the activated pool differs from `IOC_TEST_POOL`.
Never activate a production pool for this test. Each run creates a unique
fixture and prints its dataset name; no existing jail is modified or deleted.

The integration cases verify:

- Root-only rollback restores root content, leaves parent/child data unchanged,
  and removes newer snapshots.
- Recursive rollback restores parent, root, and child content.
- A missing child snapshot prevents all rollback operations without deleting
  the child dataset.
- Missing snapshots/names and running jails are rejected with the expected cause.
- A failed jail lookup makes no ZFS calls (portable) or namespace changes (native).
- ZFS errors are returned without force-destroying dependent clones.

These are filesystem fixtures, not falsely labeled runnable basejails. A separate
check creates and boots a real basejail using a fetched release:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_RELEASE=15.1-RELEASE \
    sh tests/rollback-basejail-zfs.sh
```

It verifies configuration/root bytes are restored while native compression,
current tag links and shared release bytes are not. The jail actually reads the
shared file before and after rollback. Only its uniquely named release marker
is removed on exit, and its alias is explicitly reconciled after the assertion;
the runnable jail, snapshot and logs are retained. No automatic rollback relinking
is added: a saved tag might now belong to a different jail.

## Real package-creation integration test

On a disposable FreeBSD VM, activate a dedicated test pool and fetch a complete
release first (base, lib32 where applicable, source, and the etcupdate archive).
This test needs outbound access to the configured package repositories and
installs the small `pkgconf` package inside newly created jails:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_RELEASE=15.1-RELEASE \
    sh tests/create-pkg-zfs.sh
```

It verifies relative package-list paths, successful installation, three real
package invocations despite a stdin-reading child, real failures at each template
mount layer with source diagnostics, partial-mount cleanup, first-error propagation,
no automatic start or further `count` iterations after failure, missing/empty
lists, and package installation through existing template overlays without
changing the source template. No jail is intentionally started. All newly
created datasets, templates, and logs are retained for inspection. Log paths
are printed at the start of each run; existing fixtures are not modified.

## Template and dependency failure boundaries

The opt-in native checks also include:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/template-safety-zfs.sh
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/dependent-clones-zfs.sh
```

The first verifies colliding tags cannot redirect delegated state, failures in
type/alias updates propagate after rename without updating the final flag, and
unsafe legacy template tags are refused before old datasets are destroyed.
Only its intentionally interrupted fixtures are explicitly repaired.

The second uses a new UUID-named file-backed pool without changing activation.
It verifies internal template clones can be removed non-force, outside root
and data-only clones are protected, and explicit force lists what it destroys.
Both retain logs and data fixtures. Portable migration tests additionally prove
that returned and exiting backend failures reap the spinner and keep user files.

## Tag aliases with native ZFS

With native authorization set, test both relative and absolute aliases:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/tag-links-zfs.sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TAG_ALTROOT=no sh tests/tag-links-zfs.sh
```

Each run creates an owned file-backed pool and selects its pool/root explicitly.
It checks both owners' configurations, data/GUID preservation, writer/link
errors, foreign-target rejection and unchanged original defaults. A preexisting
source alias must survive rejection or a failed link/config write. Old source
aliases are removed only after the replacement link and config write succeed;
the new alias is retained even when its name contains literal glob characters.
Returned link/write failures and interrupted updates restore both active configs
and the alias namespace, including a fault after source config replacement.
The helper reuses the normal config.old backup and one exit handler; there are
no per-tag work directories. Tests cover reassignment afterward, replacement of
dangling aliases, and literal mountpoint/tag characters. A failed rollback must
report its recovery location and retain its config.old backup. Concurrent-writer
and crash atomicity are not provided. The altroot mode does not validate the separate CLI bootstrap
path while `/iocell` already exists. Fixtures and logs are retained.

## Real template round-trip integration test

With the same disposable FreeBSD VM, activated pool and fetched release:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_RELEASE=15.1-RELEASE \
    sh tests/template-toggle-zfs.sh
```

This creates its own basejail, snapshots and delegated-data fixture. It checks
repeated jail/template round trips, UUID/tag preservation, GUIDs and snapshots,
then starts the returned jail, verifies state reporting and command execution,
and stops it. It also checks invalid UUIDs, an occupied rename destination,
running templates, and dependent root clones. The temporary collision fixture
is renamed back afterwards, not deleted.

The running-jail guard also uses a network-disabled persistent kernel jail.
Cleanup stops test jail instances; datasets, templates, clones and logs are
retained. The template under test is left with a dependent clone for inspection.

## Five high-risk safety fixes: native tests

Use only a disposable FreeBSD VM with no running jails. These tests create
small **file-backed scratch pools**, temporarily switch activation away from
`IOC_TEST_POOL`, and restore the original pool on exit. Logs, file vdevs and
scratch pools are retained; production pools must never be used.

```sh
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/safety-zfs.sh
```

Checks include parent config/data preservation with an unexpected child,
invalid generated template tags and an unrelated `/config` sentinel, failed
rename state restoration, successful template conversion, dependent and racing
clones, explicit force, fresh repeated full sends, `-i`/`-I`, clean-send ordering,
snapshot/send/receive/activation failures, and a successful move with verified
destination content and activation. Native full-stream fixtures use fresh
receivers; existing snapshot-bearing replicas use incremental streams.

Managed snapshot cleanup has a separate isolated native check:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL sh tests/send-cleanup-zfs.sh
```

It preserves unmanaged snapshot/data GUIDs, propagates an injected enumeration
failure without changing the namespace, and verifies native clone protection.
Only the test's own blocker is explicitly removed to exercise successful cleanup.
The pool/vdev and remaining fixtures are retained; activation is unchanged.
The real jail-cleanup caller must preserve parent/release send points and a
release snapshot's outside clone while removing the jails namespace.

For real remote and buffered pipelines, prepare a second disposable FreeBSD
host with root public-key SSH authentication and `mbuffer` installed on both
hosts. Allow RAM for the 1 GiB buffer at each end in addition to ZFS metadata
and host processes. Many retained test pools can substantially increase usage:

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_REMOTE=root@PRIVATE_TEST_RECEIVER \
    IOC_TEST_REMOTE_DESTRUCTIVE=yes IOC_TEST_REMOTE_POOL=RECEIVER_TEST_POOL \
    sh tests/send-remote-zfs.sh
```

Before running, explicitly mark an existing disposable receiver pool with
`zfs set org.freebsd.iocell:test=yes RECEIVER_TEST_POOL` on that receiver.
The suite requires this local (not inherited) marker and root/FreeBSD over SSH
before creating any receiver directories, vdevs, or pools.

This checks actual plain/buffered full and incremental streams, a real csh
receiver parser, intermediate snapshots, and identical pool names across hosts.
A second full receive into a snapshot-bearing destination must fail without
changing its data/GUID or source data. Actual local/remote buffer failures must
return 42 with the injected diagnostic and a retained recovery snapshot.
Remote ``-c`` must preserve a same-named local backup's snapshot/data, retain
a matching source/receiver GUID, prune older managed points, and permit the next
incremental send. A refused clean full send must retain the previous base.
A receiver-only pool must also accept a full transfer without a local namesake. Only the test's own receiver namespaces are reset between
full-stream cases; existing user data and VM disks are not deleted.
