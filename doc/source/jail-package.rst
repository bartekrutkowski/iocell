Jail images and historical differential packages
================================================

The old differential-package workflow used ``record``/unionfs and ``package``
to layer application changes over a matching vanilla release. Those command
names are not dispatched by the current CLI. Old recipes using
``create -c``, ``record start/stop`` and ``package`` are not working deployment
instructions for this checkout.

For reusable application configuration, use a stopped basejail template and
clone it; see :doc:`templates`. For a stopped jail image:

``iocell export myjail``

Ordinary exports are recursive raw ZFS streams stored under ``/iocell/images``
with identity/type/date/release in their name. They are not necessarily
``UUID.tar.xz`` archives and do not automatically get a SHA256 sidecar. A
basejail image still needs its shared release on the receiving host.

Place a trusted compatible image in the receiver's image directory and fetch
its required release, then select it by full UUID or a unique image prefix:

``iocell import FULL_IMAGE_UUID``

Verify native datasets, properties and content before setting per-jail
properties or starting it. Extra properties are not applied to ordinary stream
imports; use a separate verified ``set`` afterward. A raw ZFS receive error
returns nonzero, keeps diagnostics and does not print success. The input image
is retained, and the importer does not automatically destroy received datasets.
ZFS itself may roll back an incomplete receive; inspect any remaining partial
namespace before retrying rather than blindly removing an existing jail.

Legacy thick-jail archives use a separate import/checksum path. Match the image
to its importer rather than assuming every archive is a raw ZFS stream; see
:doc:`known-issues`.
