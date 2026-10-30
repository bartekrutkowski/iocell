Historical Debian GNU/kFreeBSD recipe
=====================================

.. warning::

   The former Squeeze/Wheezy debootstrap recipe is historical and was not
   qualified on the current FreeBSD test host. Those distributions are obsolete;
   it is not a supported contemporary Linux-jail installation guide.

GNU/kFreeBSD combined a GNU/Debian userland with a FreeBSD kernel. It must not
be confused with a Linux userland using FreeBSD's Linux compatibility layer.
Their ABI, mounts, startup services and kernel requirements differ.

``iocell create -e tag=custom-test`` can create an empty filesystem/metadata
structure for experiments. It supplies neither a userland nor the compatibility
configuration needed to boot an arbitrary operating system. A stored type or
startup-command property does not validate that setup.

Use a disposable host, a currently maintained guest userland and the matching
FreeBSD compatibility documentation before attempting such a configuration.
Do not reuse old Squeeze/Wheezy mount lists, permissive filesystem modes or
unsupported distribution repositories as a production recipe.
