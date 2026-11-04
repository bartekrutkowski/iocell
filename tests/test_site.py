"""Exercise the real site builder, Sphinx output and release selection."""
import functools
import html.parser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from urllib.parse import unquote, urlsplit

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "build_site.py"


class Links(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ("href", "src") and value:
                self.targets.append(value)


class SiteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="iocell-site-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name)
        self.source = self.base / "source with spaces"
        (self.source / "doc/source").mkdir(parents=True)
        (self.source / "web/assets").mkdir(parents=True)
        (self.source / "doc/source/conf.py").write_text(
            "project='Fixture'\nrelease='9.9.9'\nhtml_theme='classic'\n"
        )
        (self.source / "doc/source/index.rst").write_text(
            "Fixture docs\n============\n\nReal Sphinx output.\n"
        )
        (self.source / "web/index.html").write_text(
            '<!doctype html><html><head><title>iocell</title>'
            '<link rel="stylesheet" href="assets/site.css"></head><body>'
            '<a href="docs/index.html">Documentation</a>'
            '<a href="https://github.com/example/project/archive/refs/tags/'
            'v$version.tar.gz">Release $version</a></body></html>\n'
        )
        (self.source / "web/assets/site.css").write_text("body { color: #123; }\n")
        self.git("init", "-q", "-b", "master")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty",
                 "-m", "fixture")
        self.git("-c", "tag.gpgsign=false", "tag", "v2.9.0")
        self.git("-c", "tag.gpgsign=false", "tag", "v2.10.0")
        self.git("-c", "tag.gpgsign=false", "tag", "v3.0.0-rc1")
        self.git("checkout", "-q", "-b", "unmerged")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty",
                 "-m", "future")
        self.git("-c", "tag.gpgsign=false", "tag", "v99.0.0")
        self.git("checkout", "-q", "master")

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", str(self.source), *args], check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

    def build(self, output, source=None):
        return subprocess.run(
            [sys.executable, str(BUILDER), "--source", str(source or self.source),
             "--output", str(output)], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )

    def test_builds_real_docs_and_uses_released_ancestor_not_dev_version(self):
        output = self.base / "published site"
        result = self.build(output)
        self.assertEqual(result.returncode, 0, result.stdout)
        page = (output / "index.html").read_text()
        self.assertIn("Release 2.10.0", page)
        self.assertIn("v2.10.0.tar.gz", page)
        self.assertNotIn("9.9.9", page)
        self.assertNotIn("99.0.0", page)
        self.assertNotIn("$version", page)
        self.assertIn("Fixture docs", (output / "docs/index.html").read_text())
        self.assertEqual((output / "assets/site.css").read_text(),
                         "body { color: #123; }\n")
        self.assertTrue((output / ".nojekyll").is_file())
        self.assertFalse((output / "docs/.doctrees").exists())
        self.assert_local_links(output)

    def assert_local_links(self, output):
        for file in output.rglob("*.html"):
            links = Links()
            links.feed(file.read_text())
            for link in links.targets:
                url = urlsplit(link)
                if url.scheme or url.netloc or not url.path:
                    continue
                self.assertFalse(url.path.startswith("/"), (file, link))
                target = file.parent / unquote(url.path)
                if url.path.endswith("/"):
                    target /= "index.html"
                self.assertTrue(target.is_file(), (file, link))

    def test_project_homepage_and_docs_links_work_below_a_project_url(self):
        output = self.base / "project site"
        result = self.build(output, source=ROOT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assert_local_links(output)

    def test_docs_stay_light_with_dark_system_and_saved_preferences(self):
        chrome = (os.environ.get("CHROME_BIN") or shutil.which("google-chrome")
                  or shutil.which("chromium"))
        if not chrome:
            mac_chrome = pathlib.Path(
                "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            )
            if mac_chrome.is_file():
                chrome = str(mac_chrome)
        if not chrome:
            if os.environ.get("CI"):
                self.fail("Chrome/Chromium is required for the browser test")
            self.skipTest("Chrome/Chromium not installed; set CHROME_BIN")
        output = self.base / "site"
        result = self.build(output, source=ROOT)
        self.assertEqual(result.returncode, 0, result.stdout)
        (self.base / "check.html").write_text('''<!doctype html>
<html><body><pre id="result"></pre><script>
const saved = new URLSearchParams(location.search).get("saved");
if (saved === "dark") localStorage.setItem("theme", "dark");
else localStorage.removeItem("theme");
const frame = document.createElement("iframe");
frame.width = new URLSearchParams(location.search).get("width");
frame.height = "900";
frame.onload = () => {
    const doc = frame.contentDocument;
    const visible = node => node.getClientRects().length > 0;
    const result = {
        darkSystem: frame.contentWindow.matchMedia(
            "(prefers-color-scheme: dark)"
        ).matches,
        width: frame.contentWindow.innerWidth,
        background: getComputedStyle(doc.body).backgroundColor,
        scheme: getComputedStyle(doc.documentElement).colorScheme,
        toggles: [...doc.querySelectorAll("button[aria-label]")].filter(
            node => /color theme/i.test(node.ariaLabel) && visible(node)
        ).length,
        saved: localStorage.getItem("theme")
    };
    document.getElementById("result").textContent = JSON.stringify(result);
};
frame.src = "site/docs/index.html";
document.body.append(frame);
</script></body></html>''')

        class QuietHandler(SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(
            QuietHandler, directory=str(self.base)
        ))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for width, saved in ((1280, "auto"), (1280, "dark"),
                                 (390, "auto"), (390, "dark")):
                with self.subTest(width=width, saved=saved):
                    browser = subprocess.run([
                        chrome, "--headless=new", "--disable-gpu",
                        "--no-first-run", "--disable-background-networking",
                        "--force-dark-mode", "--dump-dom",
                        "--virtual-time-budget=5000",
                        "--user-data-dir=" + str(self.base / "chrome-profile"),
                        f"http://127.0.0.1:{server.server_port}/check.html"
                        f"?saved={saved}&width={width}"
                    ], capture_output=True, text=True, timeout=45)
                    self.assertEqual(browser.returncode, 0, browser.stderr)
                    # The probe contains only JSON, not page markup.
                    start = browser.stdout.index('<pre id="result">')
                    data = browser.stdout[start:].split(">", 1)[1].split("<", 1)[0]
                    self.assertTrue(data, browser.stdout)
                    rendered = json.loads(data)
                    self.assertTrue(rendered["darkSystem"], rendered)
                    self.assertEqual(rendered["width"], width, rendered)
                    self.assertEqual(rendered["background"],
                                     "rgb(255, 255, 255)", rendered)
                    self.assertEqual(rendered["scheme"], "light", rendered)
                    self.assertEqual(rendered["toggles"], 0, rendered)
                    self.assertEqual(rendered["saved"],
                                     "dark" if saved == "dark" else None)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_no_stable_tag_does_not_publish_a_preview_or_unmerged_release(self):
        self.git("tag", "--delete", "v2.9.0", "v2.10.0")
        output = self.base / "no release"
        result = self.build(output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no stable release tag", result.stdout)
        self.assertFalse(output.exists())

    def test_refuses_existing_output_without_touching_its_contents(self):
        output = self.base / "existing"
        output.mkdir()
        marker = output / "owned.txt"
        marker.write_text("preserve me\n")
        result = self.build(output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stdout)
        self.assertEqual(marker.read_text(), "preserve me\n")
        self.assertEqual(list(output.iterdir()), [marker])

    def test_refuses_output_inside_source_assets_before_writing(self):
        output = self.source / "web/assets/nested"
        result = self.build(output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside site/documentation sources", result.stdout)
        self.assertFalse(output.exists())

    def test_sphinx_error_cannot_be_published_as_a_success(self):
        (self.source / "doc/source/index.rst").write_text(
            "Fixture docs\n============\n\n.. not-a-real-directive::\n"
        )
        result = self.build(self.base / "broken")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not-a-real-directive", result.stdout)


if __name__ == "__main__":
    unittest.main()
