# Tests

Run the portable regression tests from the repository root:

```sh
sh tests/clone-snapshot.sh
sh tests/rollback.sh
sh tests/pkg-install.sh
sh tests/create-pkg.sh
```

These execute the real shell functions with mocked ZFS/system calls. They do
not require FreeBSD, root, or a ZFS pool. The clone test covers explicit and
automatic snapshot names and rejects source snapshot renaming. The rollback
test covers target selection, snapshot preflight, running jails, and error
propagation. Package tests cover list parsing, first-error propagation, release
and template selection, partial mount failures, cleanup, and cleanup failures.

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
