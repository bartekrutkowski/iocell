How to create and use templates
===============================

Templates preserve a configured jail for deployment through ZFS clones.

A stopped basejail can be converted to a template and back again using the
``istemplate`` property. Templates are not started automatically. Converting a
template back to a jail preserves its stored ``host_hostuuid``, tag, snapshots,
and child datasets; it does not give the jail a new identity.

Template tags become ZFS dataset names. Start the tag with a letter, digit or
underscore; use only letters, digits, underscores, periods, colons and hyphens.
A generated timestamp tag contains ``@`` and must first be changed explicitly,
for example with ``iocell set tag=mytemplate UUID``. An unsafe tag is rejected
before changing datasets, metadata, aliases or delegated state. Tags are not
silently rewritten.

**Here is how to create a template with iocell:**

1. Create a new jail ``iocell create tag=mytemplate``
2. Configure the jail's networking
3. Install any package you like and customize jail
4. Once finished with customization stop the jail ``iocell stop UUID | TAG``
5. A good idea is set some notes ``iocell set notes="customized PHP,nginx jail" UUID | TAG``
6. Turn the template property on ``iocell set istemplate=yes UUID|TAG``
7. List your template with ``iocell list -t``

**Here is how to use the created template:**

To create a new jail from this template simply clone it!

1. ``iocell clone TAG-of-mytemplate tag=mynewjail``
2. List new jail ``iocell list``
3. Start jail ``iocell start UUID | TAG``

Done!

**To customize or patch the template:**

Stop it if it was started for maintenance, convert it back with
``iocell set istemplate=no TAG-of-template``, then start the jail as usual.
After maintenance, stop it and convert it to a template again.

Conversion back is refused if the stored UUID is invalid, the template is
running, or its root/data datasets have clones outside the template tree. A failed ZFS rename (for
example, because the original UUID destination is occupied) is reported as an
error without changing the template flags or tag link. The previous ``jailed``
state of the template's ``data`` child dataset is restored if the rename fails;
any failure to restore it is also reported. Forward conversion likewise
renames before changing metadata or aliases, and preserves both ``on`` and
``off`` delegated states. A failed config lookup cannot edit the host's
``/config``.

``iocell clean -t`` includes clones inside the templates tree, but refuses
clones outside it. ZFS dependency protection remains enabled if an outside clone
appears after the preflight check. ``iocell clean -f -t`` prints ZFS's
complete destruction preview for the templates tree and its dependent trees
before destroying them.

A failed metadata or alias update after a successful conversion rename returns
an error; the dataset may already have moved. The final template flag is not
written after that failure.
