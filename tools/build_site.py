#!/usr/bin/env python3
"""Build the project homepage and current Sphinx documentation for Pages."""
import argparse
from pathlib import Path
import re
import shutil
from string import Template
import subprocess
import sys
import tempfile


def latest_release(source):
    tags = subprocess.run(
        ["git", "-C", str(source), "tag", "--merged", "HEAD",
         "--sort=-version:refname"], check=True, capture_output=True, text=True
    ).stdout.splitlines()
    for tag in tags:
        match = re.fullmatch(r"v([0-9]+\.[0-9]+\.[0-9]+)", tag)
        if match:
            return match.group(1)
    raise ValueError("no stable release tag found; fetch the repository's tags")


def build(source, output):
    if output.exists():
        raise ValueError(f"output already exists: {output}; choose a fresh path")
    for directory in (source / "web", source / "doc/source"):
        if output == directory or directory in output.parents:
            raise ValueError("output must be outside site/documentation sources")
    version = latest_release(source)
    template = Template((source / "web/index.html").read_text(encoding="utf-8"))
    homepage = template.substitute(version=version)
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="iocell-doctrees-") as doctrees:
        subprocess.run(
            [sys.executable, "-m", "sphinx", "-E", "-a", "-n", "-W",
             "--keep-going", "-b", "html", "-d", doctrees,
             str(source / "doc/source"), str(output / "docs")], check=True
        )
    shutil.copytree(source / "web/assets", output / "assets")
    (output / "index.html").write_text(homepage, encoding="utf-8")
    (output / ".nojekyll").write_text("")
    print(f"Built homepage for v{version} and current docs at {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path,
                        default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, default=Path("_site"))
    args = parser.parse_args()
    try:
        build(args.source.resolve(), args.output.resolve())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Site build failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
