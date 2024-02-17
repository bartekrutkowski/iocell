===========
Basic usage
===========

This section is about basic use and is a suitable quick howto for newcomers.

Fetch a release
---------------

The very first step with iocell is to fetch a RELEASE. By default iocell will attempt to fetch the
host's current RELEASE from the freebsd.org servers. Once the RELEASE bits are downloaded, the most
recent patches are applied too.

Simply run:

``iocell fetch``

If a specific RELEASE is required run:

``iocell fetch release=9.3-RELEASE``

In case a specific download mirror (FTP or HTTP) is required simply run:

``iocell fetch ftphost=ftp.hostname.org``

You can also specify a directory to fetch the base files from:

``iocell fetch ftpdir=/dir/``

Create a jail
-------------

There are three supported basic jail types: full, clone and base jail. In addition to these three 
there are two more which are discussed later (empty and templates).
Depending on requirements the `create` subcommand can be tweaked to create any of the three types.
By default iocell will create a fully independent jail of the current host's RELEASE and set the TAG property to todays date.

Creating a jail is real simple, just run:

``iocell create``

This will create a fully independent jail.

To create a lightweight jail (clone) run:

``iocell create -e``

To create a base jail:

``iocell create -b``

To create a jail and set its IP address and tag property run:

``iocell create -e tag=myjail ip4_addr="em0|10.1.1.10/24"``

For more information please read iocell(8).

Listing jails
-------------

To list all jails run:

``iocell list``

To see all downloaded RELEASEs run:

``iocell list -r``

To see available templates run:

``iocell list -t``

Start, stop or restart a jail
-----------------------------

To start or stop any jail on the system both the UUID or TAG can be used interchangeably.
To simplify UUID handling iocell accepts a partial UUID too with any subcommand.

Start
+++++

To start a jail tagged www01 simply run:

``iocell start www01``

To start a jail with a full UUID run:

``iocell start 26e8e027-f00c-11e4-8f7f-3c970e80eb61``

Or to start the jail only with a partial UUID enter the first few characters only:

``iocell start 26e8``

Stop
++++

To stop a jail just use the ``stop`` subcommand instead of start:

``iocell stop www01``

Restart
+++++++

To restart a jail run:

``iocell restart www01``

*Note: Short UUIDs are supported with all operations and subcommands within iocell.*

Configure a jail
----------------

Any property can be reconfigured with the ``set`` subcommand.

Set property
++++++++++++

To set the jail's TAG property run:

``iocell set tag=www02 26e8e027``

Get property
++++++++++++

To verify any property simply run the ``get`` subcommand:

``iocell get tag 26e8e027``

Get all properties:
+++++++++++++++++++

Or to display all supported properties run:

``iocell get all 26e8e027``

System wide defaults
--------------------

Starting with version 1.6.0 system wide defaults can be set. These defaults will be re-applied for all
newly created jails. To create a system wide default override for a property simply specify the ``default`` keyword instead of a jail UUID or TAG.

Example, to turn off VNET capability for all newly created jails run:

``iocell set vnet=off default``

Destroy a jail
---------------

To destroy a jail, simply run:

``iocell destroy www02``

**Warning:** this will irreversibly destroy the jail!
