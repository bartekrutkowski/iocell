# Documented-command audit — 2026-10-29

Historical pre-safety-fix results. See the subsequent
[five-fix verification](safety-fixes-2026-10-30.md) for changes and targeted tests.

## Result

**The current tree does not work fully as documented and should not be
release-qualified yet.**

The [case matrix](command-audit-2026-10-29.csv) contains **335 current-tree
checks: 283 PASS, 52 FAIL**. These include setup, negative/error-path checks,
and eight regression-suite wrappers; they are not counts of distinct bugs.
Nine additional baseline-comparison checks and eleven superseded attempts
are retained separately in the raw results, not included in these totals.
There are no unexecuted/BLOCKED cases in the current matrix.

This audits the working tree based on `916fe23`, including the uncommitted
template changes. No additional production fixes were made during the audit.
The new integration test's tag-link assertion was corrected: it must preserve
the actual pre-failure link state, including an absent link, rather than
assume every template has a tag symlink.

## Environment and method

- Main VM: FreeBSD 15.1-RELEASE-p6, amd64, 2 CPUs, 2 GiB RAM; real ZFS,
  jails, VNET, PF and enabled RACCT.
- Independent receiver: another private FreeBSD 15.1 VM. Remote replication
  and initialization used real SSH and ZFS streams, not mocked SSH.
- Verified 15.1 and 14.5 release fixtures; both basejail and full independent
  14.5 → 15.1 upgrades were exercised. The full upgrade was checked with
  `freebsd-version` inside its actual root, not a replacement base mount.
- CSV commands use `i` as shorthand for `(cd /root/iocell-src && sh ./iocell
  "$@")`; the driver defines that shell function for each invocation.
- Commands retain stdout/stderr, exit status and side-effect assertions.
  Assertions inspect kernel jail state, ZFS origins/snapshots/GUIDs, UCL
  properties, file contents, network addresses, MACs and resource rules.
- Console success was verified through a synchronized PTY. Package tests used
  an appropriately addressed jail. Both corrections avoid fixture false
  positives from early attempts.
- Full-OS Git fetch was retried with sufficient pool space and an OS tree
  containing mtree directory/permission metadata. Fetch, boot and execution
  passed. Earlier incomplete/ENOSPC fixtures are superseded, not product bugs.
- A thick-upgrade inspection timeout was superseded by an interactive retry
  with a longer budget; the real upgrade passed (about nine minutes).

## Safety findings to fix first

| Finding | Observed behavior | Matrix case |
| --- | --- | --- |
| Move deletes its destination | `send -m` returned 0, removed the destination `iocell` dataset, and left the source intact. Native dataset checks independently confirmed this. | `send-move` |
| Full send can silently be stale | A second full send on the same day transmitted the first daily snapshot's file content, not current source content. | `send-same-day-repeat` |
| Listing can rewrite jail metadata | An unrecognized child dataset without config caused a read-only `list` to rewrite its parent's existing config. This also interfered with a thick fixture after FreeBSD update created backup datasets. Before/after files are retained. | `readonly-list-preserves-config` |
| Failed template conversion escapes its namespace | A program-generated timestamp tag contains `@`, so conversion to a template fails at ZFS rename. It nevertheless reports success, changes metadata, and can write `istemplate=yes` into an unrelated root `/config`. A controlled sentinel proved the write; it was restored afterward. | `template-generated-tag`, `template-scope-integrity` |
| Template cleanup misses dependent clones | Confirmed, non-force `clean -t` removed a dependent jail clone. Its dependency guard misses origins on root datasets. The command warns about deletion, but the implemented non-force clone guard is ineffective. | `clean-t-dependent-guard` |
| Failed import reports success | Invalid stream data produced a ZFS receive error followed by `done!` and exit 0. | `import-invalid-stream` |

The source functions `__send`, `__clean_templates`, `__check_filesystems`,
`__find_jail`, `__console`, `__deactivate` and `__import` are byte-identical to
pre-fix base `af493c6`. Their hashes are retained in `source-provenance.json`.
Runtime comparisons against committed `916fe23` also reproduced stale version,
short-UUID, defaults setter, forced console, unknown-command, import-property,
and generated-tag/outside-`/config` failures. The destructive/migration
findings are not evidence that the pending template back-conversion patch
introduced those old defects. Not every remaining finding was bisected.

## Command coverage

Every command spelling in the current help synopsis was exercised, including
aliases, plus the four legacy documented names and the extra `pull`/`push`
dispatcher entries. Global `-v`, `-h`, `--help` and `--version` were included.
"Mixed" means valid paths passed but at least one option, error path or
published claim failed; it does not mean every invocation failed.

| Command(s) | Result and coverage |
| --- | --- |
| `activate` | PASS: switch pools, retain old data, initialize pristine namespace. |
| `cap` | PASS: actual kernel RCTL rules with RACCT enabled. |
| `clean` | Mixed: all four modes, confirmation/decline and force flag forms exercised; dependent-template-clone guard fails. |
| `clone` | PASS: normal/existing snapshots, tags, property operands and native origins/content. |
| `console` | Mixed: real interactive console works; `-f` does not start a stopped jail correctly. |
| `create` | Mixed: bare/default, normal, empty, count, properties, packages and template paths work; legacy documented modes and `base=` are rejected. |
| `deactivate` | FAIL: existing native pool discovery marker remains set. |
| `defaults` | PASS for display; writes through `set … default` fail. |
| `destroy` | Ordinary destruction, clone guards, cancellation and force work; missing operands return success, and running-jail `-f` behavior contradicts help. |
| `df` | PASS. |
| `exec` | PASS: running-jail commands, quoting, user flags and command exit status. |
| `export` | Export/restoration works; documented archive/checksum-sidecar format does not match produced files. |
| `fetch` | Mixed: explicit official release/local distribution and valid Git fixtures work; interactive release list is obsolete and ports flags do not install ports. |
| `get` | Mixed: ordinary/all/recursive reads work; short UUID, `all default`, and invalid option status fail. |
| `help` | PASS; documentation content has mismatches listed below. |
| `import` | Valid full/short-prefix images restore; corrupt streams report success and property overrides are ignored. |
| `init-host` | PASS for real receiver filesystem initialization; invalid remote pool rejected. |
| `inuse` | PASS. |
| `limits` | Rules display works; empty result returns a misleading failure status. |
| `list` | Ordinary, recursive/template and sort options work; actual ordering checked for every sort field. Read-only migration safety fails. |
| `pkg` | Networked package operations work; quoted multi-word arguments are split. |
| `promote` | PASS: actual ZFS clone promotion. |
| `rcboot`, `rcshutdown` | PASS: real lifecycle/state checks. |
| `reboot`, `restart` | Hard/soft and ALL paths exercised; default restart contradicts soft-restart documentation, and missing operands return success. |
| `reset` | PASS: single/ALL and retained identity/property checks. |
| `rollback` | PASS: stopped-only, root/recursive targeting, missing snapshots and failure handling. |
| `runtime` | PASS. |
| `send` | Local/remote full and `-i`/`-I` streams work, including intermediate snapshots. Move, same-day freshness, remote-only pool validation, clean scope and some error statuses fail. |
| `set` | Ordinary/multiple properties, space/equals notes, networking and template back-conversion work. Defaults, apostrophes and generated-tag template safety fail. |
| `snaplist`, `snapmount`, `snapremove`, `snapshot`, `snap`, `snapumount` | PASS: real snapshot, mount/unmount, removal and recursive/force paths. |
| `start`, `stop` | Valid normal/force/ALL paths work; missing operands return success. |
| `uncap` | Rule clearing/empty-state exit-status problem. |
| `update` | Ordinary base/thick paths exercised; ports options fail to provide a ports tree while reporting success. |
| `upgrade` | PASS: explicit/default targets, basejail and independent full-userland upgrade. |
| `version`, `--version` | FAIL: print stale `2.1.2`, not packaged upstream `2.2.0`. |
| `chroot`, `package`, `record start/stop`, `show` | Legacy documentation advertises these, but dispatcher does not implement them; usage is printed with success status. |
| `pull` | Extra dispatcher command: normally fetched plugin has detached checkout and pull fails silently; explicit tracking-branch workaround works. Non-Git errors also return success. |
| `push` | Extra/experimental dispatcher command: fails from the invocation directory, not the selected jail. |

## Other documentation and automation mismatches

- Basic-use documentation says default jails are fully independent; current
  help/code instead create a basejail.
- Older `create -b`, `-c`, `-t` and `base=RELEASE` forms are still documented
  but rejected. The exact attempted forms are in the CSV.
- The release menu offers 15.0-CURRENT, 14.0-RELEASE and 13.2-RELEASE, then
  rejects its own 15.1-RELEASE default. Explicit 14.5 fetch succeeded.
- Ports options depend on unavailable legacy tooling and return success
  without the promised tree.
- Remote `send` incorrectly requires the destination pool name to exist
  locally. A matching local scratch pool allowed real remote full/incremental
  transfers to pass; this is a workaround, not a clean PASS for remote send.
- `send -c` leaves non-generated snapshots despite its all-snapshots claim.
- Unknown commands, several missing operands and malformed remote increments
  return success. This is particularly unsafe in unattended workflows.
- Import properties are discarded; `pkg query '%n %v'` loses argument
  boundaries; a benign apostrophe in notes breaks shell parsing.

## Regression verification

All five retained portable suites pass under both `sh` and `dash` locally
(41 scenarios per shell): clone snapshot, rollback, package installation,
package creation and template toggle.

The retained FreeBSD integration suites pass: package creation (6 scenarios),
template toggle (7) and rollback (6). These are additional assertions inside
three of the CSV's regression wrappers, not 19 more CSV rows. The other five
wrappers run portable suites under FreeBSD `sh`.

## Evidence, scope and recovery

- CSV: all 335 current-tree cases, exact commands, expected/observed exits,
  assertions and log names. **Commands are destructive and fixture-specific;
  do not copy them into production.**
- Test-host directory: `/vms/iocell-test/command-audit/`. The final archive
  retains full JSON, drivers, context, per-case logs and controlled probes.
  Private peer SSH keys and bulky Git repositories are excluded.
- Both original VM disks have offline internal checkpoints named
  `pre-command-audit-20261029` and `audit-functional-20261029`. Restore both
  together only while the VM is shut off. Host-side recovery instructions
  are retained alongside the results.
- VM definitions/disks were not deleted. The auxiliary receiver is retained.
  The main VM was restored, with audited source/evidence copied back; only
  the bulky, verified OS Git jail was removed to leave 3.53 GiB pool headroom.
  It is running with no active jails or jail nullfs/tmpfs mounts. The retained
  receiver is powered off. Native final-health records are on the test host.
- Both NICs remain on the private libvirt network. During outbound HTTPS
  from both guests, a physical-uplink capture observed 739 frames and zero
  frames bearing either test VM MAC. No public guest interface was added.

This is a command/option audit on the stated platform, not proof of every
property/value combination, optional acceleration backend, application-level
DB consistency, other architecture, or other FreeBSD host kernel. The audit
driver is stateful and requires matching disposable fixtures/checkpoints;
it is not an unattended production test runner. Relevant individual tests
should become focused regressions as each defect is repaired.

Recommended next step: fix the data/metadata safety failures first, then
exit-status/argument handling, then reconcile obsolete documentation and
platform dependencies. Keep the template commit paused until that review.
