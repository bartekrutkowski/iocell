# Disposition of 35 review findings

Code changes through `30db920`, followed by documentation/evidence cleanup.
All findings were checked against the implementation and relevant history.
“Addressed” does not mean every proposed remedy was safe or every factual claim
was correct. No independent reviewer/subagent tool was available; these changes
received structured self-review and the verification recorded below.

## Findings

| # | Disposition and evidence |
| --- | --- |
| 1 | **Fixed** `f741641`: required root snapshots are checked before allocation; clone/config errors propagate. [Portable](../clone-snapshot.sh) and [native](../clone-zfs.sh) failures verify no premature publication. |
| 2 | **Fixed with a safer remedy** `f741641`: automatic snapshots are recursive; missing historical delegated-data snapshots cause refusal. Inventing an empty data clone was rejected because it conceals loss. Native tests compare historical/live root and data bytes and snapshot GUIDs. |
| 3 | **Fixed** `ced16ff`: reversion requires the actual template dataset before touching delegated state. [Native collision coverage](../template-safety-zfs.sh) proves a basejail's matching tag cannot redirect template data changes. |
| 4 | **Fixed** `ced16ff`: post-rename type/link failures propagate before the final flag update. Actual UCL/ln faults return 42 with root/data GUIDs retained; rename is not claimed to be rolled back after later failure. |
| 5 | **Fixed** `7f646b8`: relative links resolve against the tags directory without changing caller cwd; altroot is initialized and link/config errors checked. [Real-altroot backend tests](../tag-links-zfs.sh) and [symlink cases](../tag-links.sh) verify both owners and reject foreign targets. This does not repair the separate CLI altroot bootstrap limitation. |
| 6 | **Fixed** `08cd383`: each package child receives `/dev/null` stdin. Real package/child tests process every line rather than consuming the list. |
| 7 | **Claim rejected:** one package per line was already documented in help, basic and advanced usage. That contract remains; arbitrary shell splitting would break quoted literal names rather than fix the documented interface. |
| 8 | **Fixed** `41bd245`: the buffered receiver is a single-line command explicitly invoking `/bin/sh`. Old csh parsing failed; [real csh parser](../send-csh.sh) and [actual csh SSH streams](../send-remote-zfs.sh) now pass. |
| 9 | **Fixed** `38766c1`: `console -f` uses the resolved UUID and does not log in after failed startup. [Native tests](../console-force-zfs.sh) start an actual jail and preserve its existing JID when already running. |
| 10 | **Fixed** `bdabe01`: runtime 2.2.0 matches the existing release/tag and docs; [version aliases](../version.sh) are checked. |
| 11 | **Fixed** `b87205b`: retain the raw pair and split only its first equals sign; remove eval-based arrays. [Real UCL tests](../set-values-zfs.sh) preserve spaces, apostrophes, newlines and shell-like text literally. |
| 12 | **Fixed** `b87205b`: reserved-tag checks use the intended AND condition rather than accepting every value. |
| 13 | **Partly valid; fixed** `a2d7e79`: incomplete identities remain visible with warnings, and safe migration remains isolated. Full-UUID fast lookup was not itself hidden, so the blanket claim was too broad. [Native discovery](../discovery-zfs.sh) preserves bytes, quota/compression and data through failed/retried migration. |
| 14 | **Fixed** `a2d7e79`: bulk lifecycle actions continue after failed/unconfigured targets and report failure. A later real running jail is reached and stopped; enumeration errors propagate. |
| 15 | **Fixed** `a2d7e79`: remove stale exported discovery caches and unrelated late configuration migration scans. Existing configs/native properties are not rewritten merely by discovery. |
| 16 | **Fixed** `ced16ff`: conversion returns errors; migration preflights unsafe destinations before destruction and reaps its spinner on return or exit. [Job-control regression](../migrate-safety.sh) also passes FreeBSD sh; native preflight preserves an old child GUID/canary. This is not a transactional legacy migration redesign. |
| 17 | **Fixed** `ced16ff`: internal template clones belong to recursive cleanup; outside clones block non-force cleanup and are listed under force. [Actual ZFS tests](../dependent-clones-zfs.sh) prove internal cleanup works without `-R` and protect external root/data-only clones. |
| 18 | **Late check fixed; destructive proposal rejected** `41bd245`: receiver buffer probes precede cleanup/snapshots. Failed full snapshots are retained and named, not blindly deleted. Real receivers accept complete data before an injected buffer exit 42, demonstrating why a common recovery snapshot may still be needed. |
| 19 | **Fixed** `41bd245`: checked enumeration selects only reserved `@ioc-send-*` points within exact iocell tree boundaries. Explicit per-snapshot deletion needs neither `-r` nor `-R`; native clone protection remains. [Cleanup tests](../send-cleanup-zfs.sh) preserve user points/data/GUIDs, and errors stop send/clean-jails. Remote `-c` cannot erase a same-named local backup. |
| 20 | **Fixed** `cb4e549`: every native suite requires explicit destructive opt-in, FreeBSD/root, a locally marked pool, its mounted dataset and the expected selector before CLI initialization. [Guard tests](../native-test-guard.sh) exercise refusals. Do not mark production pools. |
| 21 | **Boundary documented/tested; implicit relinking rejected** `1b34c24`: rollback restores filesystem/config bytes, not native properties, aliases or shared release. [A real booted basejail](../rollback-basejail-zfs.sh) proves the distinction. Automatically reclaiming an old tag could collide with another jail. |
| 22 | **Duplication fixed with safety boundaries retained** `30db920`: whole public preflight runs once before initialization; private dispatch does not repeat it. Sender option extraction is one pass. Direct backend validation remains necessary. The claimed snapshot `-r` drift was not observed; positive dispatcher/native recursive snapshots remain covered. No late-only validation or parsed-global cache was introduced. |
| 23 | **Partly valid:** default-branch duplication/dead code removed in `b87205b`. “Two queries per property” was inaccurate: the second read occurs only for ambiguous unquoted `null`, distinguishing a missing value from the literal string. Independent backend name/path checks protect direct callers and were retained. |
| 24 | **Fixed** `ced16ff`: one pool-wide filesystem/volume origin guard replaces the duplicate reversion scan, covers outside root/data clones and emits blocker/query diagnostics. Unused release/duplicate tag reads are removed; [destroy tests](../destroy-guard-safety.sh) distinguish blocker 1 from query errors 8/9. |
| 25 | **Diagnostics fixed; boundary deletion rejected** `08cd383`: preserve native mount errors. Early readable-list preflight avoids allocating a jail; installer validation protects direct/time-of-use calls after lengthy creation. Both boundaries have distinct uses and coverage. |
| 26 | **Fixed** `a2d7e79`/`ced16ff`: one UUID predicate is reused by discovery, template reversion and migration rather than drifting regex copies. |
| 27 | **Fixed** `ced16ff`/`41bd245`/`30db920`: typed origin queries, no redundant stage EXIT resets, unused vars/export or dead sender argument/count branches. Actual buffer diagnostics/status 42 survive quiet progress mode. Sender endpoints remain individual argv entries. |
| 28 | **Fixed** `08cd383`: [package coverage](../create-pkg-zfs.sh) exercises all three real template mount layers, native source errors and partial cleanup, plus a stdin-reading child after actual pkg. |
| 29 | **Fixed across focused tests:** obsolete origin/clean stubs, vacuous package assertions and misleading labels removed. Empty jail-name and failed lookup are distinct; real clone blockers and failed queries have different expected causes/statuses. |
| 30 | **Fixed** `f741641`/`cb4e549`/`1b34c24`: root/data historical/live coverage, root-aware tag paths, failed-find/no-ZFS rollback and a genuinely runnable basejail. The original filesystem rollback fixture is no longer mislabeled as a basejail. |
| 31 | **Strengthened** through `30db920`: native faults must reach their intended boundary and emit their marker; template negatives require their stated cause. Race hooks, buffer 42 and retained snapshots are checked. UUID scratch pools/artifacts are reported. Useful real `/config` boundary tests remain despite portable overlap. |
| 32 | **Verified and regression added** `41bd245`: second full receives into existing snapshot-bearing replicas fail while retaining receiver data/GUID and source bytes in plain, buffered and csh modes. Subsequent real incrementals succeed. No destructive overwrite was added. |
| 33 | **Addressed:** dated reports/matrix move here, outside user docs; deployment no longer requires reading them. The provenance JSON existed inside the original archive, not the checkout: it is now recovered, linked and independently hash-checked against both recorded commits. Historical results are not rewritten as current counts. |
| 34 | **Addressed:** user docs describe operations and specific remaining limits instead of audit diaries, counts or repeated qualification prose. Obsolete notes/quoting caveats and old send-cleanup wording are corrected; historical evidence stays separate. |
| 35 | **Addressed:** soft restart describes stop/start hooks and signaling, not guaranteed graceful restart of every process; VIMAGE and RACCT/RCTL are feature-specific; send names the source tree; reset wording is explicit; duplicate template prose is removed; quickstart uses a dedicated pool. The Debian page was not literally empty (22 explanatory lines), but was not an actionable recipe, so it is preserved here rather than kept in user navigation. |

## Verification

- Runtime regression source through `30db920`: **367 PASS under sh and 367 under
  dash**, plus **231 native groups** (221 local and ten actual SSH groups).
- Native assertions include actual runnable jails, root/delegated-data bytes,
  snapshot/dataset GUIDs, exact configuration bytes, aliases, activation, native
  mount errors, package behavior, all pipeline stages and clone dependencies.
- Peer temporarily used 2 GiB for real 1 GiB buffers, then was shut off with its
  original 1 GiB domain XML restored byte-for-byte. VM definitions/disks and
  recovery checkpoints remain; guest networking stays private.
- Final documentation checks passed: strict Sphinx, regenerated manual lint,
  44 local Markdown links, all 35 disposition rows and the preserved 335 CSV
  records. Shell syntax and whitespace checks passed; final portable reruns
  repeated all 367 cases per shell without adding them twice.
- Seven historical source-provenance entries match both recorded Git revisions;
  these are provenance checks, not extra runtime scenarios.

The original 335-case audit was not rerun/reclassified; its 52 failures are not
a current bug count. Repeated regression runs are not added to these totals.

## Remaining scope

This review does not repair short UUID lookup, reset-to-saved-defaults, literal
`null` per-jail reads, multi-word `pkg` arguments, interactive release/ports
legacy paths, deactivation discovery comments, ordinary import property
operands, experimental Git synchronization, remote-only destination validation
or CLI altroot bootstrap. Remote `-c` is sender retention only. Property values,
runtime status propagation, transactions and concurrent-writer serialization
remain incomplete. See [current limitations](../../doc/source/known-issues.rst).
