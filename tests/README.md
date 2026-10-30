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
sh tests/template-forward-safety.sh
sh tests/clean-template-safety.sh
sh tests/destroy-guard-safety.sh
sh tests/import.sh
```

These execute the real shell functions with mocked ZFS/system calls. They do
not require FreeBSD, root, or a ZFS pool. The import test covers successful
full/prefix selection, corrupt/truncated receives, preserved diagnostics and
partial data, existing targets, missing images and ambiguous selection.
The clone test covers explicit and
automatic snapshot names and rejects source snapshot renaming. The rollback
test covers target selection, snapshot preflight, running jails, and error
propagation. Package tests cover list parsing, first-error propagation, release
and template selection, partial mount failures, cleanup, and cleanup failures.
Template tests cover stored UUID selection, delegated state, validation, clone
and running-jail guards, rename errors, and propagation through the CLI.
Safety tests additionally cover fresh full-send snapshots, every pipeline stage
(including both buffers), activation failures, source identity across moves,
read-only discovery, legacy-config preservation, forward conversion failures,
invalid config paths, cleanup races and propagation of dependency-query errors.

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

It verifies relative package-list paths, successful installation, partial-mount
failure cleanup, first-error propagation,
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
