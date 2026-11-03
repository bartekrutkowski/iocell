===============================
iocell - A FreeBSD jail manager
===============================

iocell manages FreeBSD jails using ZFS, shared-IP or VNET networking, templates,
clones, snapshots and optional kernel resource limits. It requires ``uclcmd``
and stores UCL configuration alongside native ZFS properties.

Start with :doc:`basic-use`. A default jail is a basejail using shared read-only
release files, not an independent OS copy. See :doc:`known-issues` for current
command restrictions and storage limitations.

`Project website <https://bartekrutkowski.github.io/iocell/>`_ ·
`Source code <https://github.com/bartekrutkowski/iocell>`_

Documentation
=============

.. toctree::
   :maxdepth: 2

   release-notes
   basic-use
   networking
   jailtypes
   best-practices
   advanced-use
   templates
   jail-package
   ezjail-migration
   known-issues
   faq

Reference
=========

``iocell help`` and the generated ``iocell(8)`` manual describe the command
interface. Their source is ``lib/ioc-help``.

* :ref:`genindex`
* :ref:`search`
