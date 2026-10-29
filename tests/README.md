# Tests

Run the portable regression tests from the repository root:

```sh
sh tests/clone-snapshot.sh
sh tests/rollback.sh
```

These execute the real shell functions with mocked ZFS/system calls. They do
not require FreeBSD, root, or a ZFS pool. The clone test covers explicit and
automatic snapshot names and rejects source snapshot renaming. The rollback
test covers target selection, snapshot preflight, running jails, and error
propagation.

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
