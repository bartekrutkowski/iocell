===============================
iocell - A FreeBSD jail manager
===============================

iocell manages FreeBSD jails using ZFS, shared-IP or VNET networking, templates,
clones, snapshots and optional kernel resource limits. It requires ``uclcmd``
and stores UCL configuration alongside native ZFS properties.

Start with :doc:`basic-use` and :doc:`known-issues`. Current verification covers
FreeBSD 15.1-RELEASE-p6/amd64, including 14.5 jail fixtures; it is not a blanket
compatibility or production-readiness guarantee. The default jail is a basejail
using shared read-only release files, not a complete independent OS copy.

The five high-risk safety paths have targeted regression coverage. Other
command defects and historical recipes are identified explicitly in these
docs rather than advertised as working current interfaces.

Documentation
=============

.. toctree::
   :maxdepth: 2

   basic-use
   networking
   jailtypes
   best-practices
   advanced-use
   templates
   jail-package
   ezjail-migration
   debian
   known-issues
   faq

Reference
=========

``iocell help`` and the generated ``iocell(8)`` manual describe the current
command interface. The source of that reference is ``lib/ioc-help``. The
repository's test guide distinguishes portable tests from opt-in destructive
FreeBSD/ZFS tests. Never run those integration tests on production data.

* :ref:`genindex`
* :ref:`search`
