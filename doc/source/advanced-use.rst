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

Updates are handled with the freebsd-update(8) utility. Jails can be updated
while they are stopped or running.

To update a jail to latest patch level run:

``iocell update UUID | TAG``

This will create a back-out snapshot of the jail automatically.

When finished with updating and the jail is working OK, simply remove the snapshot:

``iocell snapremove UUID|TAG@snapshotname``

In case the update breaks the jail, simply revert back to the snapshot:

``iocell rollback UUID|TAG@snapshotname``

If you'd like to test updating without affecting a jail, create a clone and
update the clone the same way as outlined above.

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

``iocell upgrade UUID|TAG release=10.1-RELEASE``

Upgrade basejail
++++++++++++++++

To upgrade a basejail:

Verify whether the jail is a basejail:

``iocell get type UUID|TAG``

Should return type "basejail".

The upgrade can be forced while the jail is online with executing:

  ``iocell upgrade UUID|TAG``

This will forcibly re-clone the basejail filesystems while the jail is running (no downtime) and update the jails /etc with the changes from the new RELEASE.

``iocell set release=10.1-RELEASE UUID|TAG``

This will cause the jail to re-clone its filesystems from 10.1-RELEASE on next jail start. This will not update the jails /etc files with changes from the next RELEASE.

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

Resource limits
---------------

iocell can enable optional resource limits for a jail. The outlined procedure should provide enough for
a decent starting point.

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

If you have many properties on a jail that you would like to reset back to defaults, iocell easily allows that!

To reset to defaults:

``iocell reset UUID | TAG``

You can also reset every jail to the default properties:

``iocell reset ALL``

Resetting a jail will retain the jails UUID and TAG. Everything else will be lost. Make sure to set any custom properties back that you need. If you have set anything via ``iocell set PROPERTY default`` You have nothing left to do!

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
