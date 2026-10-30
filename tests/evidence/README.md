# Historical evidence and review dispositions

These are maintenance records, not installation prerequisites or the current
user guide. Dated failure counts describe their original revisions, not current
failures. See [the test guide](../README.md) for reproducible regression commands.

- [Command audit, 2026-10-29](command-audit-2026-10-29.md) and its
  [335-case matrix](command-audit-2026-10-29.csv): based on `916fe23` with the
  explicitly described uncommitted template work.
- [Original source provenance](source-provenance.json): recovered byte-for-byte
  from `command-audit/source-provenance.json` inside the original
  `results-final.tar`. It was previously absent from the checkout, not lost from
  the audit artifacts. All seven hashes were independently recomputed against
  both recorded Git revisions. A hash covers the function's source segment up
  to the next function definition, including intervening separators/comments.
- [Five safety fixes, 2026-10-30](safety-fixes-2026-10-30.md): targeted results
  at that stage, not a reclassification of the original audit matrix.
- [35 review findings](review-findings-2026-10-30.md): fixes, rejected proposals,
  verification and remaining limitations from the subsequent review.
- [Historical Debian GNU/kFreeBSD note](debian-gnu-kfreebsd.rst): preserved as
  history, not an actionable contemporary guest installation recipe.

Raw logs, fixture datasets, file-backed pools and VM recovery checkpoints remain
on the disposable test systems described by the dated records; those private
systems are not required to use iocell or run newly provisioned regressions.
Never replay the stateful audit matrix against production data.
