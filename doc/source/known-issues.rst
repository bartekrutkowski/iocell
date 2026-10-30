Known issues and verification scope
===================================

The current command audit used FreeBSD 15.1-RELEASE-p6/amd64, real ZFS/jails,
VNET and enabled RACCT. It included 14.5-RELEASE jail fixtures and independent
14.5 to 15.1 userland upgrade. It did not qualify every host kernel,
architecture, property combination or application-level consistency guarantee.

Five high-risk paths have focused regression coverage: safe pool moves, fresh
full-send snapshots and pipeline errors, discovery that preserves existing
parent config, safe template conversion/config paths, and non-force template
clone protection. Those fixes do not resolve all other command defects.

Current command limitations
---------------------------

* **Identity:** full UUIDs and tags work. Short UUID prefixes are not reliable
  for jail lookup. Image import separately supports a unique image prefix.
* **Defaults:** ``set ... default`` now persists defaults inherited by later
  ``create`` commands; explicit creation properties override them without
  changing existing jails. Managed identity/pool/template fields and read-only
  ZFS properties are excluded. ``get all default`` still does not dump defaults;
  use ``defaults``. Reset-to-saved-defaults behavior remains unresolved: this
  fix loads saved defaults only for creation, not ``reset``.
* **Property reads:** the per-jail ``get`` path confuses a literal string
  ``null`` with an absent property. Defaults inheritance preserves the string;
  inspect the UCL file directly if that value is needed.
* **Fetch:** the interactive release list is obsolete and can reject its own
  default. Specify ``release=...`` and an appropriate mirror/path explicitly.
  Legacy ports ``-p``/``-P`` depend on unavailable tooling on the verified
  platform and can report success without installing/updating ports.
* **Deactivation:** ``deactivate`` currently prints manual removal guidance;
  it does not clear a native pool discovery comment. Do not interpret it as
  disabling jails or erasing data. Removing a ZFS dataset is a separate,
  destructive operator decision.
* **Imports:** extra property operands are not applied to ordinary ZFS-stream
  imports; set properties separately after verifying the restored data. Raw
  receive failures now return nonzero without success output, preserving the
  image and leaving any received datasets for inspection. Inspect partial
  namespaces before retrying. Legacy thick-jail archive handling is separate
  and was not changed by this error-propagation fix.
* **Image format:** ordinary exports are raw recursive ZFS streams in
  ``/iocell/images``, not necessarily a compressed archive plus checksum file.
  Legacy thick-jail archive import has a separate checksum path. Do not
  assume all export/import paths create or verify SHA256 sidecars.
* **Arguments:** a multi-word ``pkg`` argument can be split. Property values
  passed to ``create`` and ``set`` preserve spaces, quotes and equals signs.
* **Exit status:** malformed command syntax, unknown commands/options and
  missing required operands now fail before pool/filesystem setup or dispatch.
  The full argument list is checked before lifecycle targets or cleanup flags
  are acted on. This does not make multi-target operations transactional or
  fix all runtime status propagation. Empty ``limits`` and ``uncap`` can still
  return failure despite an empty or cleared rule set. Verify intended state,
  not only the exit code.
* **Git:** normal plugin fetch can leave a detached checkout, so ``pull`` may
  fail without propagating the failure. ``push`` is unfinished and uses the
  invocation directory. Do not rely on these experimental dispatcher entries
  as a supported synchronization/deployment workflow.
* **Legacy names:** ``chroot``, ``record``, ``package`` and ``show`` are not
  dispatched. Historical differential packaging recipes are not available;
  see :doc:`jail-package`.

Storage and destructive operations
----------------------------------

A default-created jail is a basejail, sharing read-only release directories.
``create -e`` is empty, not a clone. Old ``create -b``, ``-c``, ``-t`` and
``base=...`` examples are obsolete. Changing a type label alone does not
populate an independent OS tree.

Template conversion rejects unsafe tags before mutation. Generated timestamp
tags contain ``@`` and need explicit retagging. A failed rename preserves
metadata/aliases and restores delegated state; a later configuration error is
reported, not a promise of an atomic transaction spanning every operation.
Non-force ``clean -t`` retains clone protection; explicit force can destroy
clones outside the templates namespace too.

Full sends create unique fresh snapshots and propagate pipeline failures.
ZFS may refuse a full receive over an existing snapshot-bearing replica: use
incremental streams or explicitly prepare a fresh destination. Remote send
still incorrectly requires the destination pool name to exist locally. Pool
names may be identical on different hosts; that is not a local self-send.

Legacy ``send -c`` cleanup selects snapshot paths containing ``ioc-``. It does
not guarantee removal of all snapshots, and remote cleanup scope is not fully
implemented. Inspect snapshots and do not rely on remote ``-c`` as a retention
policy. Do not delete a source backup merely because another command printed
``done!``.

Normal snapshots cover the jail root only; recursive snapshots include the
configuration and descendants. Shared release datasets are outside jail-root
rollback. Multi-dataset rollback is not atomic, and newly created descendants
can prevent recursive rollback rather than being silently destroyed.

Basejail updates change a shared release, potentially affecting every jail
using it. Use a maintenance window and back up the shared release separately.
An automatic jail back-out snapshot is not a complete shared-release backup.

Historical kernel notes
------------------------

Older releases had an 88-character mount-path limitation and iocell's
``hack88`` workaround. This is historical guidance, not evidence that a
current host needs it. If investigating that specific issue, use a stopped
jail and an explicit target, for example ``iocell set hack88=1 myjail``.
Changing a creation default does not alter an existing jail.

Reports of VNET teardown crashes and PF/ALTQ interactions in FreeBSD 10 are
historical, not blanket statements about current kernels. Check the exact
host release, advisories and firewall configuration. A soft restart is
explicitly ``iocell restart -s TAG``; default restart is hard stop/start.

IPv6 address-detection delays can affect services binding immediately at jail
startup. Diagnose address readiness and service ordering. Globally setting
``net.inet6.ip6.dad_count=0`` disables duplicate-address detection for the host
as well; it is not an automatically safe or generally required setting.

Property names and some values are validated, but not every kernel/property
combination. Consult ``jail(8)``, ``zfs(8)`` and ``rctl(8)`` for the host version.
Do not assume a stored value means the requested kernel behavior was applied.
