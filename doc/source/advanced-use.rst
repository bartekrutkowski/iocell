==============
Advanced usage
==============

Clones
------

When a jail is cloned, iocell creates a ZFS clone filesystem.
In a nutshell clones are cheap lightweight writable snapshots.

A clone depends on its source snapshot and filesystem.
If you'd like to destroy the source jail and preserve its clones
you need to promote the clone first, otherwise the source jail cannot be destroyed.

Create a clone
++++++++++++++

To clone www01 to www02 run:

``iocell clone www01 tag=www02``

To clone a jail from an existing snapshot:

``iocell clone www01@snapshotname tag=www03``

Promoting a clone
+++++++++++++++++

**To promote a cloned jail, simply run:**

``iocell promote UUID | TAG``

The above step will reverse the clone and source jail relationship.
Basically the clone will become the source and the source jail will be demoted to a clone.

**Now you can remove the demoted jail with:**

``iocell destroy UUID | TAG``

Updating jails
--------------

Updates use ``freebsd-update(8)`` where supported by the selected userland.
Use a maintenance window and stop affected services/jails for predictable
results. A basejail update changes its shared release and can affect every
jail using that release; it is not isolated to the named jail.

To update a jail to latest patch level run:

``iocell update UUID | TAG``

Non-basejail updates create a jail-root back-out snapshot. That snapshot
does not back up a shared basejail release. Back up the shared release and
application data separately before updating basejails.

When finished with updating and the jail is working OK, simply remove the snapshot:

``iocell snapremove UUID|TAG@snapshotname``

If a suitable jail snapshot exists, stop the jail before restoring it:

``iocell rollback UUID|TAG@snapshotname``

A clone is useful for testing writable jail data, but it can still use the
same shared release as its source. Do not assume updating a basejail clone
isolates shared base updates; use a separate test release/host when necessary.

To clone run:

``iocell clone UUID|TAG tag=testupdate``

Upgrading jails
---------------

Upgrades are handled with the freebsd-update(8) utility.
By default the upgrade command will try to upgrade the jail
to the hosts RELEASE version (uname -r).

Based on the jail "type" property, upgrades are handled differently
for basejails and non basejails.

Upgrade non-basejail
++++++++++++++++++++

To upgrade a normal jail (non basejail) to the hosts RELEASE run:

``iocell upgrade UUID | TAG``

This will upgrade the jail to the same RELEASE as the host.

To upgrade to a specific release run:

``iocell upgrade UUID|TAG release=15.1-RELEASE``

Upgrade basejail
++++++++++++++++

To upgrade a basejail:

Verify whether the jail is a basejail:

``iocell get type UUID|TAG``

Should return type "basejail".

Fetch the target release, stop the jail, and run:

``iocell upgrade UUID|TAG release=15.1-RELEASE``

This selects the new shared base and merges ``/etc`` using etcupdate. Inspect
merge output and test the jail before returning it to service. There is no
application-level zero-downtime guarantee. Independent full-userland upgrades
may require interactive confirmations and several installation passes.

Setting ``release=15.1-RELEASE`` alone changes the selected base on the next
start, but does not merge ``/etc``. It is not equivalent to completing an
upgrade.

Auto boot
---------

Make sure ``iocell_enable="YES"`` is set in ``/etc/rc.conf``.

To enable a jail to auto-boot during a boot, simply run:

``iocell set boot=on UUID|TAG``

Boot priority
+++++++++++++

Boot order can be specified by setting the priority value:

``iocell set priority=20 UUID|TAG``

Lower value means higher boot priority.

Snapshot management
-------------------

iocell supports transparent ZFS snapshot management out of the box.
Snapshots are point-in-time copies of data, a safety point to which a jail can be reverted at any time.
Initially snapshots take up almost no space as only changing data is recorded.

List snapshots for a jail with:

``iocell snaplist UUID|TAG``

To create a new snapshot run:

``iocell snapshot UUID|TAG``

This will create a snapshot based on current time.

If you'd like to create a snapshot with custom naming run:

``iocell snapshot UUID|TAG@mysnapshotname``

A normal snapshot covers only the jail's root dataset. To include the jail's
configuration and all descendant datasets, take a recursive snapshot:

``iocell snapshot -r UUID|TAG@mysnapshotname``

Stop the jail before restoring a snapshot:

``iocell stop UUID|TAG``

``iocell rollback UUID|TAG@mysnapshotname``

Rollback restores only the root dataset for a normal snapshot, or the jail
configuration and descendant datasets for a recursive snapshot. All targets
must have the requested snapshot before rollback starts. A descendant created
after a recursive snapshot therefore prevents rollback; iocell will not delete
it automatically. Native ZFS properties and tag symlinks are not restored;
a saved tag property can differ from the current alias namespace. Review that
namespace before explicitly retagging a jail. Shared basejail release datasets
are not restored.

.. warning::

   Rollback discards changes and newer snapshots on the affected datasets.
   Multi-dataset rollback is not atomic. If ZFS reports an error, iocell stops
   immediately, but earlier datasets may already have been restored.

Resource limits
---------------

Resource limits require kernel RACCT/RCTL support and RACCT enabled at boot
(``kern.racct.enable=1`` in the loader configuration). Check
``sysctl kern.racct.enable`` before using these examples. Verify actual kernel
rules, not just stored property values.

Limit core or thread
++++++++++++++++++++

Limit a jail to a single thread or core number 1:

``iocell set cpuset=1 UUID|TAG``
``iocell start UUID|TAG``

List applied rules
++++++++++++++++++

List applied limits:

``iocell limits UUID|TAG``

Limit DRAM use
++++++++++++++

Limit a jail to 4G DRAM memory use (limit RSS memory use can be done on-the-fly):

``iocell set memoryuse=4G:deny UUID|TAG``

Turn on resource limits
+++++++++++++++++++++++

Turn on resource limiting for jail:

``iocell set rlimits=on UUID|TAG``

Apply limits
++++++++++++

Apply limit on-the-fly:

``iocell cap UUID | TAG``

Check limits
++++++++++++

Check active limits:

``iocell limits UUID | TAG``

Limit CPU use by %
++++++++++++++++++

Limit CPU execution to 20%:

``iocell set pcpu=20:deny UUID|TAG``
``iocell cap UUID|TAG``

Check limits:

``iocell limits UUID | TAG``

Resetting a jail's properties
+++++++++++++++++++++++++++++

Record custom properties before requesting a reset:


``iocell reset UUID | TAG``

You can also reset every jail to the default properties:

``iocell reset ALL``

Reset carries forward the jail's UUID, tag, generated VNET MAC addresses and
selected networking/type fields. It uses built-in values for other properties;
it does not reload defaults saved by ``set PROPERTY=value default``. Those saved
values apply to later ``create`` commands. Use explicit ``set`` commands when
changing an existing jail to your chosen settings.

Replication and moves
---------------------

``iocell send backup-pool`` creates a fresh unique recursive snapshot of the
active pool's ``iocell`` tree and sends it to the destination. Existing
snapshot-bearing replicas may need incremental streams rather than another
full receive:

``iocell send -i source-pool/iocell@before -i source-pool/iocell@after backup-pool``

Use ``-I`` on both endpoints to include intermediate snapshots. Remote mode
requires ``-r -u USER -h HOST`` and public-key SSH. Destination validation still
incorrectly requires a matching local pool name, even for remote sends.

``iocell send -m new-pool`` is local only and requires stopped jails. The
original source is removed only after successful transfer, destination
activation and mounting. Snapshot, sender, receiver and optional buffer
failures are errors. A failed activation retains data but may have relocated
the source mountpoint; inspect state and explicitly reactivate the source
before resuming operations.

``-c`` removes only reserved ``ioc-send-*`` snapshots under the iocell tree,
without deleting dependent clones. Local transfers clean both ends; remote
transfers clean only the sender, leaving receiver retention to the operator.
A failed full transfer reports and retains its source snapshot for recovery.

Automatic package installation
------------------------------

Packages can be installed automatically at creation time!

Specify the ``pkglist`` property at creation time, which should point to a text file
containing one package name per line. Please note you need to have Internet
connection for this to work as ``pkg install`` will try to get the packages from
online repositories.

**Example:**

Create a pkgs.txt file and add package names to it.

``pkgs.txt``:

    ::

        nginx
        tmux

Now simply create a jail and supply the pkgs.txt file:

``iocell create pkglist=/path-to/pkgs.txt tag=myjail``

This will install ``nginx`` and ``tmux`` in the newly created jail.
