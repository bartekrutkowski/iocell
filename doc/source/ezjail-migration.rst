Migration from ezjail
=====================

There is no automatic ezjail conversion command in the current CLI. Earlier
archive-copy examples were written for FreeBSD 10.1 and a particular 2015
layout. Inspect the actual archive structure instead of assuming that layout.

Treat migration as a backup/restore and compatibility exercise:

1. Record the old jail's complete configuration, release, installed packages,
   addresses, storage mounts and application-specific recovery requirements.
2. Take verified backups and test extraction into a disposable directory.
   Check archive member paths before extraction; do not assume an ``ezjail/``
   prefix or copy untrusted absolute/traversal paths into a live jail root.
3. Fetch an appropriate release and create a stopped, explicitly named target
   with the desired network mode. Current ``create`` makes a basejail; the old
   ``-b``/``-c`` flags are not the interface.
4. Stop the source before the final data copy. Selectively restore application
   data and configuration into the target's writable directories. Do not
   overwrite iocell's parent config, identity or shared read-only base mounts.
5. Reconcile packages, users, permissions, services, mounts and release-specific
   configuration. An old ezjail archive is not an ``iocell import`` stream.
6. Test startup, data integrity and networking in isolation. Keep production
   addresses and automatic boot disabled until validation is complete.
7. Retain the original data and a rollback plan until the migration is accepted.

Inspect the target's actual configuration and data after each migration step.
See :doc:`basic-use`, :doc:`jailtypes` and :doc:`known-issues`.
