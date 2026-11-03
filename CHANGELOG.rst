Changelog
=========

2.3.0 (unreleased)
------------------

This release changes failure handling and destructive-operation safeguards.
Review automation and recovery procedures before upgrading from 2.2.0. Existing
jails are not automatically migrated to newly saved creation defaults.

Commands and compatibility
~~~~~~~~~~~~~~~~~~~~~~~~~~

* Multi-jail start, stop, reboot/restart and synchronous rc operations attempt
  every selected jail and return the first reported failure. Earlier successes
  are not undone. Priority-99 background boot remains asynchronous; its failures
  are reported in logs, not in the synchronous boot status.
* Many previously hidden discovery, execution, package, configuration, kernel,
  storage and transfer failures now return nonzero. Scripts relying on old exit
  codes may need changes. This is **not** complete status normalization: some
  legacy execution paths still report misleading statuses. Inspect resulting
  state; valid multi-target commands are not transactions.
* Invalid command syntax fails before filesystem initialization.
* **Disabled in 2.3.0:** experimental ``push``. The old code was marked
  "NOT WORKING YET" and operated in the caller's working directory rather than
  reliably selecting the jail's repository. It could stage unrelated files and
  push the wrong repository. Use Git directly in an explicitly selected
  worktree; iocell does not provide a replacement deployment/push command.
* **Rejected in 2.3.0:** ``fetch -p``, ``fetch -P``, ``update -p`` and
  ``update -P``. These used obsolete portsnap-based shared ports management.
  Manage a ports checkout separately with Git, or use packages; no new
  iocell ports-management backend replaces these options.
* **Validation corrections, not removed working support:** ``update -n`` remains
  a Git-jail remote-status check, now using the correct worktree and rejecting
  other jail types. Ordinary-image property operands, previously silently
  ignored, now fail explicitly; apply properties with ``set`` after import.
  Legacy tar-archive import still accepts creation properties.
* **Previously unavailable, not new 2.3.0 removals:** ``create -b/-c/-t`` and
  ``base=`` recipes were already unsupported in 2.2.0 despite older docs.
  ``chroot``, ``record``, ``package`` and ``show`` were already undispatched.
  Corrected examples use ``release=``, ``clone`` and template/image workflows;
  this release does not restore those historical interfaces.
* ``exec ALL`` attempts all discovered jails and returns the first failure.
  Quoted exec/pkg arguments, including multiword package query formats, retain
  their argument boundaries. Package children cannot consume the package list.
* Git fetch/merge failures stop later update work. Automatically selected plugin
  release branches retain tracking upstreams; explicit tag/commit refs may
  intentionally produce detached checkouts.

Releases and upgrades
~~~~~~~~~~~~~~~~~~~~~~

* Fetch requires complete sources (normally ``src.txz``) to prepare etcupdate.
  The interactive release selection accepts safe current/mirror release names.
  Existing prepared releases are patched, never re-extracted. Local distribution
  fetches skip network patching.
* Processing an existing release requires **every iocell jail on the host to be
  stopped**, including thick jails and jails on other releases or pools. A first
  fetch of a new release has no such guard.
* Failed fetches retain partial data/cache and restore the original resolver
  where possible. An incomplete retained release blocks retries rather than
  being overwritten. Inspect it and back it up, then use the manual ZFS
  cleanup instructions in basic usage or ``iocell help``; ``clean -r`` deletes all
  releases and is not a per-release retry command.
* Ordinary basejail upgrades require a stopped jail, complete target sources and
  no preexisting child mounts. In-place upgrades of template-based basejails are
  refused; use a target-release template. Existing ``etc.old`` or upgrade
  snapshots block another upgrade until inspected and deliberately retired.
* Build/merge errors and unresolved conflicts stop upgrades and trigger backout
  of the old configuration/root where possible. Warnings alone are not conflicts.
  Mail queue creation and ``newaliases`` remain part of successful upgrades;
  their failures now enter the same checked backout path.
* Successful upgrades retain ``etc.old``, the upgrade snapshot and ``config.old``
  for inspection. Failed backout is reported without deleting recovery objects;
  an available failed-merge log is retained as ``upgrade.log``. Upgrades of
  independent userlands remain a separate, potentially interactive workflow.

Storage, configuration and startup
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* ``clean -r`` stops all jails discovered in the selected iocell tree before
  removing its shared releases. Cleanup failures propagate; failed ZFS operations
  do not authorize recursive host directory deletion. ``clean -j`` preserves
  retained-template aliases, removes internal jail clones with their tree and
  refuses outside dependent clones.
* Export refuses running jails and existing final/partial image paths. Failed
  streams and recovery snapshots are retained. Ordinary images are raw recursive
  ZFS streams, not automatically checksummed tar archives. Ordinary-stream import
  rejects property operands; set properties after restoring. Legacy tar archives
  keep property-aware creation and report late extraction failures.
* Snapshot clone/rollback selection uses the requested historical snapshot and
  preserves delegated-data boundaries. Missing required snapshots, receive
  failures and unsafe dependent-clone destruction are no longer hidden.
* Configuration writes retain one overwritten ``config.old`` last-write backup,
  not an accumulating history or a multi-property transaction. Literal property
  values, including the string ``null``, are distinct from missing keys.
* Retagging checks mounted dataset ownership. Returned alias-retirement errors
  restore both configs and aliases where possible. Failure deleting a final
  alias backup explicitly reports that the retag has already committed.
* Saved defaults affect later ordinary creation, not clones/imports/existing
  jails. Reset-to-builtins and guidance-only ``deactivate`` behavior are unchanged.
* Startup refuses to run a jail with ``rlimits=on`` if its limits cannot be
  applied. Empty successful RCTL queries and completed removals return zero.
* Background rc boot logs moved from predictable ``/var/tmp`` paths to protected
  ``${iocroot}/log/UUID-rcboot.log``. Log-directory preparation failure prevents
  startup. Root selection follows the selected dataset's actual mounted path,
  including literal altroot paths, without a global ``zfs mount -a``.
