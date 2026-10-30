Best practices
==============

Try operational changes in a disposable environment and keep recoverable
backups. See :doc:`known-issues` for current command and storage limitations.

Identify and back up jails
--------------------------

Use meaningful tags and record full UUIDs. Do not rely on partial UUID prefixes
for jail operations. Template tags must be safe ZFS components, not generated
timestamp names containing ``@``. Quote notes for the invoking shell; property
values preserve spaces, apostrophes and equals signs.

Take application-consistent backups before updates or destructive operations.
A normal snapshot covers the jail's root only. Use ``snapshot -r`` when you need
configuration and descendants, and back up shared release datasets separately.
Stop the jail before rollback. Multi-dataset rollback is not atomic.

Restart deliberately
--------------------

``iocell restart TAG`` is a hard stop/start. Use ``iocell restart -s TAG`` when
you want to retain the kernel jail and network stack while running its configured
stop/start commands and signaling remaining processes. Neither method guarantees
application consistency; follow the application's shutdown/recovery requirements.

Isolate networking and firewall changes
---------------------------------------

Set ``vnet=off`` explicitly for shared-IP examples. For VNET, prepare the bridge,
addresses, routes and firewall policy before starting the jail. An isolated
private bridge with host routing/NAT is appropriate when extra MAC addresses
must not reach a provider uplink. iocell does not configure that NAT policy for
you. Do not blindly bridge a public NIC or disable bridge filtering globally.

Per-jail firewall availability depends on the host kernel, permissions and
device exposure. Keep a working host firewall and management access while
testing changes. Historical FreeBSD 10 VNET/PF/ALTQ reports are not a current
kernel compatibility guarantee.

Resource limits and templates
-----------------------------

Enable RACCT at boot before using RCTL limits. Begin with observation/logging
and enforce limits only after measuring the workload. Empty limit queries and
``uncap`` have known exit-status quirks; inspect actual kernel rules.

Templates are useful for repeatable deployment. Stop a template and convert it
back with ``istemplate=no`` for normal start/console maintenance. The historical
``iocell chroot`` command is not dispatched. Do not casually substitute a host
``chroot(8)`` without understanding mounts and its lack of jail isolation.

Clean up explicitly
-------------------

Remove snapshots only after checking their clone dependencies. ``clean -t``
includes internal template clones but protects outside clones, including racing
ones. Explicit ``clean -f -t`` permits outside-clone destruction. Other cleanup modes remove complete
namespaces and must never be used as generic housekeeping without reviewing
what is stored there.

For replication, use incremental streams for existing replicas. Full sends
create fresh unique snapshots and fail rather than silently reusing stale data.
Keep the source until receive and activation have succeeded; even after a
successful move, verify your applications and backups before retiring storage.
