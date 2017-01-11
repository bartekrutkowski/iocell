iocell
======

**A FreeBSD jail manager.**

iocell is a zero dependency, drop in jail/container manager amalgamating some
of the best features and technologies the FreeBSD operating system has to offer.
It is geared for ease of use with a simple and easy to understand command syntax.

It has been forked from iocage, when iocage has been abandoned, but not released
by its author. This fork's goal is purely to support 'classic iocage' experience
and add fixes and features requested by iocage users.

iocell is in the FreeBSD ports tree as sysutils/iocell.
To install using binary packages, simply run: `pkg install iocell`

## WARNING:
The `develop` branch may not be functional at any given point. This is where a lot of experimental work gets done. No guarantees for stability or migrations within the branch are given. Things can and do change rapidly. **_Please don't use it if you require stability._**

- **Discussions**: Mailing list is available on [Google Groups](https://groups.google.com/forum/#!forum/iocell)
- **Contributing**: If you would like to submit a pull request, we kindly ask you to open it against the `develop` branch.

####Raising an issue:

We _like_ issues! If you are having trouble with `iocell` please open a GitHub [issue](https://github.com/bartekrutkowski/iocell/issues) and we will ~~run around with our hair on fire~~ look into it. Before doing so, please give us some information about the situation:
- Tell us what version of FreeBSD you are using with something like `uname -ro`
- It would also be helpful if you gave us the output of `iocell version`
- Most importantly, try to be detailed. Simply stating "I tried consoling into a jail and it broke" will not help us very much. However, saying something like this helps much, much more:


"I tried to console into a _template_ jail, but it failed with _this error_ in which _I pasted below:_"
````
gasgiant ~ # iocell list -t
JID  UUID                                  BOOT  STATE  TAG     TYPE
-    XXXXXXXX-XXXX-XXXX-a5be-3417ebb13845  off   down   pepperd  template
gasgiant ~ # iocell console salted
cannot open 'zroot/iocell/jails/XXXXXXXX-XXXX-XXXX-a5be-3417ebb13845': dataset does not exist
cannot open 'zroot/iocell/jails/XXXXXXXX-XXXX-XXXX-a5be-3417ebb13845': dataset does not exist
[: -ne: unexpected operator
  ERROR: jail: pepperd is not running!
````
- Use the [Markdown Basics](https://help.github.com/articles/markdown-basics/#code-formatting) GitHub page for more information on how to paste lines of code and terminal output. 

**FEATURES:**
- Templates, clones, basejails, fully independent jails
- Ease of use
- Zero configuration files
- Rapid thin provisioning within seconds
- Automatic package installation
- Virtual networking stacks (vnet)
- Shared IP based jails (non vnet)
- Resource limits (CPU, MEMORY, etc.)
- Filesystem quotas and reservations
- Dedicated ZFS datasets inside jails
- Transparent ZFS snapshot management
- Binary updates
- Differential jail packaging
- Export and import
- And many more!

**QUICK HOWTO:**

Fetch a release:

`iocell fetch`

Create a jail:

`iocell create tag=myjail ip4_addr="em0|192.168.1.10/24"`

Start the jail:

`iocell start myjail`

**USAGE:**
```
  iocell activate ZPOOL
  iocell cap UUID|TAG
  iocell chroot UUID|TAG [command]
  iocell clean [-a|-r|-j]
  iocell clone UUID|TAG [UUID|TAG@snapshot] [property=value]
  iocell console UUID|TAG
  iocell create [-b|-c|-e] [release=RELEASE] [pkglist=file] [property=value]
  iocell deactivate ZPOOL
  iocell defaults
  iocell destroy [-f] UUID|TAG
  iocell df
  iocell exec [-u username | -U username] UUID|TAG|ALL command [arg ...]
  iocell export UUID|TAG
  iocell fetch [release=RELEASE | ftphost=ftp.hostname.org | ftpdir=/dir/ |
                ftpfiles="base.txz doc.txz lib32.txz src.txz"]
  iocell get property|all UUID|TAG
  iocell help
  iocell import UUID [property=value]
  iocell init-host IP ZPOOL
  iocell inuse UUID|TAG
  iocell limits [UUID|TAG]
  iocell list [-b|-t|-r]
  iocell package UUID|TAG
  iocell promote UUID|TAG
  iocell rcboot
  iocell reboot UUID|TAG
  iocell rcshutdown
  iocell record start|stop UUID|TAG
  iocell reset UUID|TAG|ALL
  iocell restart UUID|TAG
  iocell rollback UUID|TAG@snapshotname
  iocell runtime UUID|TAG
  iocell set property=value UUID|TAG
  iocell show property
  iocell snaplist UUID|TAG
  iocell snapremove UUID|TAG@snapshotname|ALL
  iocell snapshot UUID|TAG [UUID|TAG@snapshotname]
  iocell start UUID|TAG
  iocell stop UUID|TAG
  iocell uncap UUID|TAG
  iocell update UUID|TAG
  iocell upgrade UUID|TAG [release=RELEASE]
  iocell version | --version
  ```

**REQUIREMENTS**
- FreeBSD 9.3-RELEASE amd64 or newer
- ZFS file system
- Optional - Kernel compiled with:

        # This is optional and only needed if you need VNET and resource
        # limits

        options         VIMAGE # VNET/Vimage support
        options         RACCT  # Resource containers
        options         RCTL   # same as above

**OTHER CONSIDERATIONS**
- For resource limiting please read rctl(8)
- For the explanations on jail properties read jail(8)
- Create bridge0 and bridge1 interfaces

**HINTS**
- Use iocell set/get to modify properties
- To understand what most properties do read iocell(8).
- If using VNET consider adding the following to `/etc/sysctl.conf` on the host:

        net.inet.ip.forwarding=1       # Enable IP forwarding between interfaces
        net.link.bridge.pfil_onlyip=0  # Only pass IP packets when pfil is enabled
        net.link.bridge.pfil_bridge=0  # Packet filter on the bridge interface
        net.link.bridge.pfil_member=0  # Packet filter on the member interface
