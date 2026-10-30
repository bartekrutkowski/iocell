==========
Jail types
==========

Use ``iocell get type TAG`` to inspect the stored type. The current creation
interface differs from older full/thin/base flag examples.

Basejail (default)
------------------

``iocell create tag=myjail`` creates a basejail. Writable configuration/data live
in its jail datasets; base directories are mounted read-only from a shared
fetched release using ``nullfs(5)``. This is not a fully independent OS image.
Keep the corresponding release available for startup and package operations.

Updating shared base files affects every jail using that release. A jail-root
snapshot or rollback does not include that shared release dataset. Plan backups
and maintenance accordingly.

Clone
-----

Create a clone from an existing jail or template:

``iocell clone source-tag tag=mycopy``

Or select an existing root snapshot:

``iocell clone source-tag@snapshot-name tag=mycopy``

Its root dataset is a writable ZFS clone and depends on its source snapshot.
``iocell promote mycopy`` reverses the ZFS clone dependency; it does not make
shared basejail release directories into private OS copies. Check native ZFS
origins before removing source datasets. ``create -c`` is not supported.

Template
--------

A stopped basejail can become a template using:

``iocell set istemplate=yes source-tag``

Use a safe dataset-component tag first. Templates are listed with
``iocell list -t`` and are not started automatically. Deploy a new jail with:

``iocell clone template-tag tag=mynewjail``

Convert back with ``iocell set istemplate=no template-tag``. The stored UUID,
tag, snapshots and child datasets are preserved. The old ``template=yes``
property is not the conversion interface. See :doc:`templates` for guards and
failure behavior.

Empty
-----

``iocell create -e tag=empty-test`` creates an empty filesystem/metadata
structure, not a populated FreeBSD installation or a clone. Supply a compatible
userland and appropriate startup commands before trying to run it. This is a
foundation for custom setups, not a promise of support for an arbitrary guest OS.

Independent/full (legacy thick jail)
------------------------------------

The code can operate on complete independent userlands, including legacy
``thickjail`` images and Git-backed full OS trees. A type label alone does not
populate such a userland. Current ``create`` does not provide the old ``-t``
full-jail mode; ``-b``, ``-c`` and ``base=...`` recipes are also obsolete.

Independent 14.5 to 15.1 userland upgrade was tested, but not every legacy image
format or custom guest OS. Do not assume an exported basejail includes its
shared release files; see :doc:`jail-package` and :doc:`known-issues`.
