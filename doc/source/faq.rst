FAQ
===

**What is iocell?**
    A shell-based FreeBSD jail manager using ZFS, optional VNET networking and
    optional kernel resource limits. It needs ``uclcmd``; it is not a
    zero-dependency tool.

**What is a jail?**
    FreeBSD OS-level virtualization: isolated userlands share the host kernel.
    A jail is not a VM with an independent guest kernel.

**What is VNET?**
    A separate per-jail networking stack. Shared-IP jails instead use selected
    addresses on host interfaces. Set the mode explicitly when following an
    example because capable hosts enable VNET automatically.

**How do I configure addresses?**
    Use ``ip4_addr`` or ``ip6_addr`` with ``interface|address/prefix``. The
    interface is a host interface for shared IP and a jail interface for VNET.
    See :doc:`networking`.

**Do I need a default gateway?**
    VNET jails need appropriate routes for destinations off their attached
    network. The gateway may be the host's private bridge address when the
    host is configured as a router/NAT gateway, or another router. Shared-IP
    jails use the host network stack rather than a separate jail gateway.

**Does iocell configure NAT?**
    No complete host NAT policy is set up automatically. Configure FreeBSD
    routing and firewall/NAT rules for your topology. Do not expose additional
    MAC addresses on a provider link that prohibits them.

**Can I run a firewall in a jail?**
    Availability depends on VNET, the host kernel, jail permissions and device
    exposure. Do not apply an old blanket PF/IPFW or securelevel recipe to all
    host versions. Keep host filtering and management access while testing;
    per-jail firewall policy was not qualified by the command audit.

**Can I use templates and clones?**
    Yes. Use ``istemplate=yes/no`` for conversion and ``clone`` for deployment.
    Template tags must be safe ZFS components. See :doc:`templates` and
    :doc:`jailtypes`. The historical differential ``record``/``package`` commands
    are not available.

**Are clones independent?**
    A ZFS clone depends on its source snapshot. Promotion reverses that
    relationship. Shared basejail release mounts remain shared; promotion alone
    does not turn them into a private full OS installation.

**Can I limit CPU and memory?**
    Yes, with appropriate kernel support and RACCT enabled at boot. Configure
    ``rlimits=on`` and desired properties, then inspect actual rules with
    ``limits`` and resource use with ``inuse``. See :doc:`advanced-use`.

**Can I use short UUIDs?**
    Use tags or full UUIDs for jail commands. Short UUID lookup is currently
    unreliable. Import's unique image-prefix selector is a separate mechanism.

**Where is configuration stored?**
    In UCL files under the selected iocell dataset, plus native ZFS properties.
    ``defaults`` displays defaults; the system-wide setter is currently broken.

**Can I run without a ZFS pool?**
    No. The host OS itself need not be installed on ZFS, but iocell requires a
    usable pool for jail storage.

**How do I keep iocell from managing my bridges?**
    Prepare the bridge yourself and use ``createbridge=off`` and
    ``keepbridge=on`` as appropriate. See :doc:`networking`.

**Is every documented workflow qualified?**
    No. Current verification targets FreeBSD 15.1-RELEASE-p6/amd64, including
    14.5 jail fixtures. Historical recipes and remaining command defects are
    identified in :doc:`known-issues`; do not assume success text proves state.
