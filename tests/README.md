# Tests

Run the portable regression tests from the repository root:

```sh
sh tests/clone-snapshot.sh
sh tests/rollback.sh
sh tests/pkg-install.sh
sh tests/create-pkg.sh
sh tests/template-toggle.sh
sh tests/send-safety.sh
sh tests/discovery-safety.sh
sh tests/bulk-jails.sh
sh tests/template-forward-safety.sh
sh tests/clean-template-safety.sh
sh tests/destroy-guard-safety.sh
sh tests/import.sh
sh tests/defaults.sh
sh tests/cli-args.sh
sh tests/native-test-guard.sh
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

## CLI syntax and native entrypoint tests

`cli-args.sh` exercises the real preflight and dispatcher with inert command
handler boundaries, plus direct send preflight. Shared failure cases live in
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
failure. Cleanup removes the temporary kernel jail; datasets/logs are retained.
Portable bulk tests cover start/stop/reboot/restart continuation and enumeration
failures without relying on pipelines that can hide discovery status.

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
- Missing snapshots/names and running jails are rejected.
- ZFS errors are returned without force-destroying dependent clones.

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

For real remote and buffered pipelines, prepare a second disposable FreeBSD
host with root public-key SSH authentication and `mbuffer` installed on both
hosts. Allow sufficient RAM for the existing 1 GiB buffer at each end (the
verification VMs used 2 GiB each temporarily):

```sh
IOC_TEST_POOL=YOUR_TEST_POOL IOC_TEST_REMOTE=root@PRIVATE_TEST_RECEIVER \
    sh tests/send-remote-zfs.sh
```

This checks actual plain/buffered full and incremental streams, intermediate
snapshots, identical pool names across different hosts, and real local/remote
buffer failures after a completed stream. It creates a matching local receiver
pool name because the separate, pre-existing remote-pool validation bug has
not been changed. Only the test's own receiver namespaces are reset between
full-stream cases; existing user data and VM disks are not deleted.
