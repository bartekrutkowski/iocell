===========
Basic usage
===========

Start with a disposable host or pool. These examples use ``www01`` as a tag;
replace ``zroot``, release names, interfaces and addresses for your environment.
Use a full UUID or tag, not a short UUID prefix. See :doc:`known-issues` for
remaining command limitations.

Activate a pool and fetch a release
-----------------------------------

Activate an existing ZFS pool first:

``iocell activate zroot``

Then request an available release explicitly:

``iocell fetch release=15.1-RELEASE``

The interactive ``iocell fetch`` menu is obsolete and can reject its own
current-host default. An explicit release avoids that selection path. If the
legacy default mirror/path is unavailable, specify both, for example:

``iocell fetch release=15.1-RELEASE ftphost=download.freebsd.org ftpdir=/releases/amd64/amd64/15.1-RELEASE``

The architecture and directory must match the host and distribution server.
The downloader also supports ``ftplocaldir=/path/to/distributions`` for local
release archives. Use trusted distribution files and verify their provenance;
do not assume every download/import path verifies a checksum.

Fetched releases include the base files and etcupdate data needed to create
basejails. The fetch/update paths can apply patches with ``freebsd-update(8)``.
Inspect their output and the resulting release before deploying it. Legacy
``-p``/``-P`` ports options do not work on the verified modern platform.

Create a jail
-------------

``iocell create`` creates a **basejail** using the host's release and a generated
timestamp tag. Fetch that release first. Its base directories are mounted
read-only from the shared release when the jail starts; they are not an
independent copy of the complete OS.

Prefer a meaningful tag and explicit networking mode:

``iocell create release=15.1-RELEASE tag=www01 vnet=off ip4_addr="em0|192.168.1.10/24"``

Replace ``em0`` with your actual host interface and choose an unused address.
VNET is enabled automatically on capable hosts unless overridden; its bridge
and network configuration differ from this shared-IP example.

``iocell create -e tag=empty-test`` creates an empty jail filesystem. It is not
a lightweight clone and cannot boot a FreeBSD userland until that filesystem
has been populated appropriately. Use ``iocell clone SOURCE tag=copy`` for a
clone of an existing jail or template. Legacy ``create -b``, ``-c``, ``-t`` and
``base=...`` recipes are rejected. See :doc:`jailtypes`.

Installing packages during creation
+++++++++++++++++++++++++++++++++++

Create a readable text file containing one package name per line, for example
``pkgconf``. Blank lines and lines beginning with ``#`` are ignored:

``iocell create tag=www01 vnet=off pkglist=/path/to/packages.txt``

Relative list paths are resolved from the invocation directory. The selected
release or template is mounted for installation and unmounted afterwards. An
empty list is allowed; a missing or unreadable list is rejected before creating
a jail.

Creation stops on the first package or mount error. The failed jail is retained
for inspection, but is not started or reported as successfully created. With
``count``, remaining jails are not created. Packages installed before an error
are not rolled back. Failed unmounts are also errors: inspect reported mounts
before retrying or deleting the fixture.

Listing and lifecycle
---------------------

``iocell list`` lists jails, ``iocell list -r`` lists fetched releases and
``iocell list -t`` lists templates. The ``-s`` option selects a sort field; see
``iocell help`` for the supported fields.

Start and stop by tag or full UUID:

``iocell start www01``

``iocell stop www01``

A normal restart stops and recreates the jail:

``iocell restart www01``

For a soft restart that retains the kernel jail and networking, specify ``-s``:

``iocell restart -s www01``

Console and commands
--------------------

``iocell console www01`` opens a shell in an already running jail.
``console -f`` has a known stopped-jail startup defect; start the jail explicitly
first. To run a command without an interactive console:

``iocell exec www01 /bin/sh -c 'echo ready'``

The historical ``iocell chroot`` subcommand is not dispatched. A manually
prepared ``chroot(8)`` is not a replacement for jail isolation and requires
careful mount/dependency handling. For a stopped template, convert it back to
a jail before normal start/console operations; see :doc:`templates`.

Properties and defaults
-----------------------

Set and inspect a per-jail property:

``iocell set tag=www02 www01``

``iocell get tag www02``

``iocell get all www02``

``iocell defaults`` displays configured defaults. The documented historical
``iocell set property=value default`` setter is currently broken, and
``iocell get all default`` does not dump all defaults. Specify required
properties on creation or per jail rather than relying on that setter.

Some property values are only partially validated. A benign apostrophe in a
notes value currently breaks argument parsing; avoid it until the parser is
fixed. The known-issues chapter records these limitations rather than treating
unsupported examples as working commands.

Destroy a jail
--------------

``iocell destroy www02`` asks for confirmation and refuses a running jail.
Stop the jail first for a deliberate teardown. ``iocell destroy -f www02``
bypasses confirmation and may stop a running jail before destroying it.

.. warning::

   Destruction is irreversible. Verify identity, dependent clones and backups.
   Several unrelated commands still return success for missing operands or
   invalid requests; never treat a zero exit status alone as proof of the
   intended state. Explicit template force-cleanup can destroy dependent clones.
