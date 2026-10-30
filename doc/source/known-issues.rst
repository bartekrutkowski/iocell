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
* **Defaults:** ``defaults`` displays configuration, but ``set ... default``
  currently fails. Specify per-jail properties. ``get all default`` does not
  dump the default configuration.
* **Console:** start a stopped jail explicitly before ``console``. Its ``-f``
  startup path is broken; this is distinct from ``start -f`` for a template.
* **Fetch:** the interactive release list is obsolete and can reject its own
  default. Specify ``release=...`` and an appropriate mirror/path explicitly.
  Legacy ports ``-p``/``-P`` depend on unavailable tooling on the verified
  platform and can report success without installing/updating ports.
* **Deactivation:** ``deactivate`` currently prints manual removal guidance;
  it does not clear a native pool discovery comment. Do not interpret it as
  disabling jails or erasing data. Removing a ZFS dataset is a separate,
  destructive operator decision.
* **Imports:** extra property operands are ignored by the dispatcher. Set
  properties after a verified import. A malformed stream can print a receive
  error followed by success; inspect native datasets, config and content.
* **Image format:** ordinary exports are raw recursive ZFS streams in
  ``/iocell/images``, not necessarily a compressed archive plus checksum file.
  Legacy thick-jail archive import has a separate checksum path. Do not
  assume all export/import paths create or verify SHA256 sidecars.
* **Arguments:** a multi-word ``pkg`` argument can be split; a benign apostrophe
  in a notes value breaks shell parsing. Avoid these forms until fixed.
* **Exit status:** several missing-operand/unknown-command paths return success.
  Empty ``limits`` and ``uncap`` can instead return failure despite an empty or
  cleared rule set. Verify intended state, not only the exit code.
* **Version:** the runtime banner still prints ``2.1.2``. Include the installed
  package version or checkout commit when reporting a problem.
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
jail and an explicit target, for example ``iocell set hack88=1 myjail``;
do not rely on the broken system-wide default setter.

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
