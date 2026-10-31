Known limitations
=================

Command restrictions
--------------------

* **Identity:** use full UUIDs or tags; short UUID prefixes are unreliable for
  jail lookup. Image import separately supports unique image prefixes.
* **Defaults:** saved defaults apply to later ordinary ``create`` commands, not
  existing, cloned or imported jails. ``reset`` does not reload saved creation
  defaults. ``get all default`` does not dump them; use ``defaults``.
* **Property reads:** per-jail ``get`` confuses the literal string ``null`` with
  an absent value. The UCL configuration can still contain that string.
* **Fetch:** the interactive release menu is obsolete; specify ``release=...``
  and the distribution mirror/path explicitly. Legacy ports options rely on
  obsolete tooling and can report success without installing a ports tree.
* **Deactivation:** ``deactivate`` prints manual removal guidance; it does not
  clear the native pool discovery comment or disable existing jails.
* **Imports:** property operands are not applied to ordinary stream imports.
  Set properties separately after restoring. Failed imports retain the image
  and any partial datasets; inspect that namespace before retrying.
* **Image format:** ordinary exports are raw recursive ZFS streams, not an
  archive/checksum pair. Legacy thick-jail archives use a separate import path;
  not every image format supplies or verifies SHA256 sidecars.
* **Arguments:** multi-word ``pkg`` arguments can be split. Quote property
  values for the invoking shell; ``create`` and ``set`` preserve them literally.
* **Runtime errors:** syntax errors fail before initialization, but valid
  multi-target commands are not transactional. Property/kernel validation and
  runtime status propagation remain incomplete. Empty ``limits`` and ``uncap``
  can return failure despite an empty or cleared rule set.
* **Git:** plugin fetch can leave a detached checkout, and ``pull`` failures may
  be masked. Experimental ``push`` uses the invocation directory. These are not
  a complete synchronization/deployment interface.
* **Legacy names:** ``chroot``, ``record``, ``package`` and ``show`` are not
  dispatched. See :doc:`jail-package` for the available image workflow.
* **Altroots:** automatic CLI selection can use the wrong configuration path
  when the usual ``/iocell`` already exists alongside an altroot pool. Check
  actual mountpoints before creating jails in that layout.

Storage boundaries
------------------

Basejails share read-only release directories. ``create -e`` supplies an empty
filesystem, not a clone or independent OS. Changing a type label does not copy
an OS tree. Shared-release updates affect every basejail using that release;
back it up separately and use a maintenance window.

Template conversion requires a safe dataset tag; generated timestamp tags
containing ``@`` must be retagged first. A failed rename preserves metadata and
delegated state. A later metadata or alias failure is reported, but the dataset
may already have moved. ``clean -t`` removes the whole templates tree, including
internal clones; only explicit force permits destruction of outside clones.

A full receive can be refused by ZFS when the destination already has snapshots.
Use incremental streams or a fresh destination, not an automatic destructive
replacement. Remote sends validate their destination on the receiver.
Remote ``-c`` cleans only sender retention; manage receiver snapshots separately.
Cleanup removes older reserved ``ioc-send-*`` snapshots after success, keeping
the new replication point and never deleting dependent clones.
Failed full transfers retain and name their source snapshot for recovery.

Normal snapshots cover root only; recursive snapshots include configuration and
descendants. Rollback does not restore native properties, tag links or the shared
release. The saved tag can differ from current aliases. New descendants can
block recursive rollback; multi-dataset rollback can stop after earlier targets
have already been restored. Take application-consistent backups separately.

Kernel and networking notes
---------------------------

VNET needs VIMAGE support; RACCT/RCTL are required only for resource limits.
A stored property does not prove that the host kernel applied it. Consult
``jail(8)``, ``zfs(8)`` and ``rctl(8)`` for the host version.

The old 88-character mount-path issue and ``hack88`` workaround concern historic
kernels. Do not enable it as a general prerequisite. Likewise, old FreeBSD 10
VNET/PF/ALTQ reports are not blanket descriptions of current kernels.

IPv6 services can race address readiness during startup. Diagnose address and
service ordering rather than globally disabling duplicate-address detection:
``net.inet6.ip6.dad_count=0`` affects the host as well as its jails.
