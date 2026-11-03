===========
Basic usage
===========

Use an existing dedicated jail pool. These examples call it ``jailpool`` and
use ``www01`` as a tag; replace pool/release names, interfaces and addresses.
See :doc:`known-issues` for command restrictions and storage boundaries.

Activate a pool and fetch a release
-----------------------------------

Activate the dedicated pool first, not the host's boot pool:

``iocell activate jailpool``

Then request an available release explicitly:

``iocell fetch release=15.1-RELEASE``

If the default mirror/path is unavailable, specify both, for example:

``iocell fetch release=15.1-RELEASE ftphost=download.freebsd.org ftpdir=/releases/amd64/amd64/15.1-RELEASE``

The architecture and directory must match the host and distribution server.
The downloader also supports ``ftplocaldir=/path/to/distributions`` for local
release archives. Use trusted distribution files and verify their provenance;
do not assume every download/import path verifies a checksum.

Fetched releases include the base files and etcupdate data needed to create
basejails. The fetch/update paths can apply patches with ``freebsd-update(8)``.
Inspect their output and the resulting release before deploying it. Legacy
``-p``/``-P`` ports options rely on obsolete tooling; use current FreeBSD package
or ports management instead.

Processing an existing release (including a repeated fetch to patch it) requires
**every iocell jail on the host to be stopped**, including thick jails and jails
on other releases or pools. This conservative guard is host-wide, not a check of
which jails share this release. A first fetch of a new release has no such guard.

Recover an incomplete fetch
+++++++++++++++++++++++++++

A failed fetch retains its datasets and cache. A retry refuses an incomplete
release rather than re-extracting over potentially valuable data. Inspect and
back up that data before deciding to discard it. Stop all iocell jails and check
the exact pool, release, mounts, snapshots and clone dependencies. For an
**unneeded incomplete** ``15.1-RELEASE`` in the example ``jailpool`` only::

    zfs list -r jailpool/iocell/releases/15.1-RELEASE
    zfs list -r jailpool/iocell/download/15.1-RELEASE
    zfs destroy -r jailpool/iocell/releases/15.1-RELEASE
    zfs destroy -r jailpool/iocell/download/15.1-RELEASE
    iocell fetch release=15.1-RELEASE

This deletes the partial release and its cached archives; substitute your actual
pool/release, omit commands for absent datasets and never discard a needed
release. Keep valid archives separately if you want to reuse them. Do not add
``-R`` or ``-f`` to overcome a dependent clone or busy mount, and do not
recursively remove host directories after a failed ZFS command. ``clean -r``
removes **all** releases, not a single incomplete release.

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
``base=...`` recipes were already unsupported in 2.2.0 despite older docs; these
are not newly removed creation modes. See :doc:`jailtypes` and
:doc:`release-notes` for supported workflows and compatibility changes.

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
before retrying or deleting the failed jail.

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

For a soft restart, retaining the kernel jail and networking, specify ``-s``:

``iocell restart -s www01``

This runs the configured stop/start commands and signals remaining processes;
it does not guarantee graceful shutdown or recovery of every application.

Console and commands
--------------------

``iocell console www01`` opens a shell in an already running jail.
``iocell console -f www01`` starts it first if stopped, then opens the console.
A failed startup returns an error without attempting login. To run a command
without an interactive console:

``iocell exec www01 /bin/sh -c 'echo ready'``

For a stopped template, convert it back to a jail before normal start/console
operations; see :doc:`templates`.

Properties and defaults
-----------------------

Set and inspect a per-jail property:

``iocell set tag=www02 www01``

``iocell get tag www02``

``iocell get all www02``

Per-jail configuration writes retain one ``config.old`` last-write backup
beside ``config``. Later writes overwrite it; tag recovery may consume it.
It is not a jail backup or a backup of an entire multi-property command.

``iocell defaults`` displays configured defaults. Set defaults for subsequent
``create`` commands with ``iocell set vnet=off default``, and inspect one with
``iocell get vnet default``. Explicit creation properties override saved
defaults; existing jails and cloned/imported configurations are unchanged.
``iocell get all default`` still does not dump all defaults.

Defaults are stored in the selected pool's ``.default`` UCL file. Generated
identity/runtime fields, active-pool selection, template selection/conversion
and read-only ZFS properties cannot be set as creation defaults; see
``iocell help`` for the exact list. Writable native defaults such as
``compression`` affect new jail datasets, not existing datasets or their
parent. Invalid names, empty values, invalid on/off switches and failed UCL
writes leave the setting unchanged. Other value validation is incomplete;
a stored string is not proof that every kernel combination will work.
Multiple settings are independent updates, not a batch transaction.

Malformed syntax fails before pool/filesystem setup. Valid multi-target commands
are not transactional: a runtime failure can follow earlier successful changes.
Some property values are only partially validated. Quote values for the invoking
shell; spaces, apostrophes and equals signs are preserved literally.

Destroy a jail
--------------

``iocell destroy www02`` asks for confirmation and refuses a running jail.
Stop the jail first for a deliberate teardown. ``iocell destroy -f www02``
bypasses confirmation and may stop a running jail before destroying it.

.. warning::

   Destruction is irreversible. Verify identity, dependent clones and backups.
   Explicit template force-cleanup can also destroy clones outside its tree.
