==========
Networking
==========

Jails can share selected host IP addresses or have a separate VNET stack.
IOC functions configure jail interfaces, not an entire upstream routing,
firewall or NAT policy. Use addresses and interface names appropriate to your
host; examples below are private test networks.

VNET-capable hosts enable VNET automatically for newly created jails unless
``vnet=off`` is specified. Set the mode explicitly to avoid confusing host
interfaces such as ``em0`` with jail interfaces such as ``vnet0``.

Shared IP
---------

For an existing stopped jail:

``iocell set vnet=off ip4_addr="em0|192.168.1.10/24" myjail``

Replace ``em0`` with the actual host interface. Choose an unused address, not
an address already assigned to another machine or reserved by DHCP. Multiple
addresses can be comma-separated:

``iocell set ip4_addr="em0|192.168.1.10/24,em0|192.168.1.11/24" myjail``

IPv6 uses the analogous property, for example an appropriate private ULA on
an interface that supports it:

``iocell set ip6=new ip6_addr="em0|fd77::10/64" myjail``

Start and inspect the jail:

``iocell start myjail``

``iocell exec myjail ifconfig``

Shared-IP addresses are assigned through the host interface; this does not
create a separately routed VNET stack. A jail does not need its own default
router in this mode. Stop removes managed aliases, so do not reuse the host's
management address as a jail alias.

``allow_raw_sockets=1`` permits operations such as ping when appropriate to
your security policy. It is not a substitute for routes or firewall rules.
Use ``iocell set vnet=off default`` to make shared-IP mode the default for
subsequent ``create`` commands. Explicit creation properties override saved
defaults. Existing jails need an explicit per-jail setting and any required
restart; changing a creation default does not reconfigure their networking.

VNET
----

Use a kernel with VNET support. Current GENERIC kernels commonly include it;
check your host rather than rebuilding from a historical FreeBSD 10 recipe.
RACCT/RCTL are resource-limit features, not prerequisites for VNET itself.

An isolated private bridge example on the host is:

.. code-block:: sh

   ifconfig bridge0 create
   ifconfig bridge0 inet 10.77.0.1/24 up

Then configure a stopped jail:

``iocell set vnet=on interfaces=vnet0:bridge0 createbridge=off keepbridge=on ip4_addr="vnet0|10.77.0.2/24" defaultrouter=10.77.0.1 myjail``

``iocell start myjail``

``iocell exec myjail ifconfig vnet0``

This bridge has no physical member. It provides a private host/jail link, not
automatic Internet connectivity. For outside access, configure host forwarding,
routes and, if required, NAT and firewall rules for this subnet. The upstream
must have a return route unless NAT supplies it. Persist the host bridge and
address in ``rc.conf`` using your existing networking conventions.

.. warning::

   Do not add a provider-facing physical NIC to this bridge if extra MAC
   addresses are prohibited. A physical-member bridge is an L2 network and
   can expose jail MACs upstream. Use a private bridge with routing/NAT instead.
   Retain private management access while testing firewall/routing changes.

A physical-member bridge is an alternative only where the upstream network
explicitly permits that topology. Its configuration is site-specific; blindly
copying ``addm em0`` or VLAN-parent instructions can disrupt host connectivity.

IPv6 VNET configuration uses the jail interface, not the host NIC:

``iocell set ip6_addr="vnet0|fd77::2/64" defaultrouter6="fd77::1" myjail``

The gateway must exist on the attached network, and IPv6 forwarding and firewall
policy must be configured on the router. No public/global IPv6 address is
required for an isolated test network.

Inspecting and maintaining networks
-----------------------------------

Use ``iocell get vnet myjail``, ``iocell exec myjail ifconfig`` and host
``ifconfig(8)``, ``netstat(1)`` and firewall tools to verify actual state.
Only running jails accept ``exec`` or normal ``console`` operations.

``iocell restart myjail`` destroys and recreates the jail/networking;
``iocell restart -s myjail`` requests a soft restart retaining them.

Bridge filtering sysctls and packet-filter rules depend on the intended
security boundary. Do not universally disable ``pfil`` to obtain connectivity.
Likewise, disabling IPv6 duplicate-address detection globally is not a default
workaround: it affects the host as well as jail addresses.

To request no addresses or gateways:

``iocell set ip4_addr=none ip6_addr=none defaultrouter=none defaultrouter6=none myjail``

This alone does not configure an otherwise missing bridge or give a shared-IP
jail a VNET stack. ``createbridge=off`` leaves bridge creation to the operator;
``keepbridge=on`` requests retaining a bridge during jail shutdown. Review other
jails using a bridge before changing or deleting it.

Private shared IPv4/IPv6, isolated VNET IPv4/IPv6, multiple VNET interfaces and
MACs, DHCP and alias cleanup were exercised in the command audit. Arbitrary
provider, VLAN, per-jail firewall and routing configurations were not qualified.
