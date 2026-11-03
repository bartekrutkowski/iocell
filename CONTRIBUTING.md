# Contributing

Keep changes focused and describe the bug or behavior they address. Include
reproduction steps and relevant test results in pull requests. Discuss larger
interface changes before implementing them.

## Shell style

- Target FreeBSD `/bin/sh`; do not introduce bash-only syntax.
- Use four spaces per indentation level, not tabs. Wrap near 80 columns.
- Quote variable expansions unless intentional list splitting is required.
- Use `&&` and `||` between tests rather than ambiguous `test -a`/`test -o`.
- Name internal functions `__function_name` and function variables `_variable`.
  Keep variables local, or isolate helpers in a subshell when their traps or
  temporary state must not affect callers.
- Check commands that can fail. Preserve meaningful failure statuses, stop
  unsafe follow-up actions, and report retained data or recovery files.

## Testing

See [tests/README.md](tests/README.md) for portable and native suites. Add a
regression that fails before a bug fix and checks the resulting behavior, not
source text. Keep real callers in the test path where possible.

Native suites are destructive. Use disposable FreeBSD hosts and explicitly
marked test pools; follow the authorization requirements for both sender and
receiver. Verify failure preservation as well as successful effects. State
which suites were run and distinguish mocked boundaries from native operations.

## Documentation

Edit `lib/ioc-help` when changing the command reference, then regenerate both
manual files on FreeBSD with `txt2man` installed:

```sh
sh ./iocell help > iocell.8.txt
txt2man -d "$(date '+%Y-%m-%d')" -t iocell -s 8 \
    -v "FreeBSD System Manager's Manual" iocell.8.txt > iocell.8
mandoc -Tlint -Wwarning iocell.8
```

Commit the generated manuals with their source. Keep examples current and the
runtime banner aligned with the project release in `doc/source/conf.py`.
Validate Sphinx pages and internal references in a separate Python environment:

```sh
sphinx-build -E -a -n -W --keep-going -b html doc/source /tmp/iocell-doc-html
```

Do not commit generated HTML to source branches, private lab reports, host
details, or test logs.

## Project website

The homepage is maintained in `web/`; documentation remains in `doc/source/`.
The site builder needs Python 3.13 or newer and a Git checkout with release tags.
It selects the newest stable tag reachable from the checkout for source
downloads, while documentation follows the checked-out source.

```sh
git fetch --tags
python3 -m venv /tmp/iocell-pages-venv
/tmp/iocell-pages-venv/bin/pip install -r doc/requirements-pages.txt
/tmp/iocell-pages-venv/bin/python -m unittest discover -s tests -p test_site.py
site="$(mktemp -d /tmp/iocell-site.XXXXXX)"
/tmp/iocell-pages-venv/bin/python tools/build_site.py --output "${site}/html"
/tmp/iocell-pages-venv/bin/python -m http.server 8000 --bind 127.0.0.1 \
    --directory "${site}/html"
```

Choose a fresh output directory: the builder refuses to overwrite an existing
path. It builds Sphinx with warnings treated as errors, keeps build caches
outside the published tree, and preserves underscore-prefixed static assets.

`.github/workflows/pages.yml` checks pull requests and builds pushes to
`master`. Only `master` publishes generated files to `gh-pages`, retaining that
branch's history. The workflow explicitly requests a Pages build because a
push made with `GITHUB_TOKEN` alone does not trigger one. Keep Pages configured
to publish the root of `gh-pages`; no custom domain or extra token is needed.
After creating a release tag, use **Actions → Project site → Run workflow** on
`master` to refresh the release download link if no new commit is being pushed.
