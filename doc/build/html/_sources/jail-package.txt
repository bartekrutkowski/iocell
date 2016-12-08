Create a jail package!
======================

**What is a jail package?**
  A jail package is basically a small differential image template which can be
  deployed on top of vanilla jails.
  The RELEASE and patch level has to match between the package and a vanilla jail.

iocell uses the **record** function for this, which is a **unionfs** mount
under the hood.

The resulting package can be stored on a web server with a checksum file ready
to be deployed anywhere.

1. create a new jail ``iocell create -c tag=nginx``
2. start jail ``iocell start UUID | TAG`` 
3. configure networking to enable internet access for this jail
4. issue ``iocell record start UUID | TAG``, from now on every change will be recorded
   under ``/iocell/jails/UUID/recorded``
5. install nginx with ``pkg install nginx``
6. install any other software you might require
7. customize configuration files
8. once finished, stop recording changes with ``iocell record stop UUID | TAG``
   optionally stop jail
9. examine ``/iocell/jails/UUID/recorded``, run ``find
   /iocell/jails/UUID/recorded -type f``
10. remove any unnecessary files, make final customization/changes
11. run ``iocell package UUID | TAG``, this will create a package in
    ``/iocell/packages`` with a SHA256 checksum file
12. optionally discard the jail now with ``iocell destroy UUID | TAG``

The resulting ``UUID.tar.xz`` can now be deployed on top of any new vanilla
jail!

1. create new jail ``iocell create -c``
2. deploy package ``iocell import UUID tag=myjail``
3. list jail ``iocell list|grep myjail``, grab UUID
4. start jail ``iocell start UUID | TAG``
5. examine your changes and packages - they are all there!

Enjoy!

