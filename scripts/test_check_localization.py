"""Tests for check-localization.py (run: python3 -m unittest scripts/test_check_localization.py)."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check-localization.py"


def catalog(entries):
    return {
        "sourceLanguage": "en",
        "version": "1.0",
        "strings": {
            key: {
                "extractionState": "manual",
                "localizations": {
                    "en": {"stringUnit": {"state": "translated", "value": en}},
                    "tr": {"stringUnit": {"state": "translated", "value": tr}},
                },
            }
            for key, (en, tr) in entries.items()
        },
    }


class CheckLocalizationTests(unittest.TestCase):
    def run_check(self, swift: str, entries: dict) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            sources = Path(tmp) / "src"
            sources.mkdir()
            (sources / "View.swift").write_text(swift, encoding="utf-8")
            catalog_path = Path(tmp) / "Localizable.xcstrings"
            catalog_path.write_text(json.dumps(catalog(entries)), encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(SCRIPT), "--sources", str(sources), "--catalog", str(catalog_path)],
                capture_output=True, text=True)

    def test_clean_source_passes(self):
        result = self.run_check('let a = String(localized: "k.one \\(name)")', {"k.one %@": ("One %@", "Bir %@")})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_and_unused_keys_fail(self):
        result = self.run_check('let a = String(localized: "k.missing")', {"k.unused": ("U", "K")})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("k.missing", result.stderr)
        self.assertIn("k.unused", result.stderr)

    def test_untranslated_turkish_fails(self):
        result = self.run_check('let a = String(localized: "k")', {"k": ("K", "")})
        self.assertNotEqual(result.returncode, 0)

    def test_every_literal_is_reported_with_line_numbers(self):
        swift = "\n".join([
            'Text("a")',
            '.help("b")',
            'Window("c", id: "x")',
            'ContentUnavailableView("d", systemImage: "e")',
            '.confirmationDialog("f", isPresented: $p) {}',
            'ProgressView("g")',
            'MenuBarExtra("h", systemImage: "i") {}',
            'alert.messageText = "j"',
            'alert.addButton(withTitle: "k")',
            'Text(verbatim: "ok")',
        ])
        result = self.run_check(swift, {})
        self.assertNotEqual(result.returncode, 0)
        for line in range(1, 10):
            self.assertIn(f"View.swift:{line}", result.stderr)
        self.assertNotIn("View.swift:10", result.stderr)

    def test_complex_interpolation_fails(self):
        result = self.run_check('let a = String(localized: "k \\(a.b)")', {"k %@": ("K %@", "K %@")})
        self.assertNotEqual(result.returncode, 0)

    def test_literals_in_comments_are_ignored_but_line_numbers_hold(self):
        swift = "\n".join([
            '// Text("a")',
            '/* Button("b")',
            '   .help("c") */',
            'let u = "https://example.com" ; Text("d")',
            'let k = String(localized: "k") // Text("e")',
        ])
        result = self.run_check(swift, {"k": ("K", "K")})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("View.swift:4", result.stderr)
        for line in (1, 2, 3, 5):
            self.assertNotIn(f"View.swift:{line}:", result.stderr)

    def test_localized_key_inside_string_with_slashes_survives(self):
        result = self.run_check('let a = String(localized: "see // here")', {"see // here": ("S", "S")})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_accessibility_label_link_and_nsmenuitem_are_reported(self):
        swift = "\n".join([
            '.accessibilityLabel("a")',
            'Link("b", destination: u)',
            'NSMenuItem(title: "c", action: nil, keyEquivalent: "")',
            '.accessibilityLabel(String(localized: "k"))',
        ])
        result = self.run_check(swift, {"k": ("K", "K")})
        self.assertNotEqual(result.returncode, 0)
        for line in (1, 2, 3):
            self.assertIn(f"View.swift:{line}:", result.stderr)
        self.assertNotIn("View.swift:4:", result.stderr)

    def test_duplicate_catalog_keys_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            sources = Path(tmp) / "src"
            sources.mkdir()
            (sources / "View.swift").write_text('let a = String(localized: "k")', encoding="utf-8")
            unit = '{"stringUnit": {"state": "translated", "value": "V"}}'
            body = '{"sourceLanguage": "en", "strings": {"k": {"localizations": {"en": %s, "tr": %s}}, "k": {"localizations": {"en": %s, "tr": %s}}}}' % (unit, unit, unit, unit)
            catalog_path = Path(tmp) / "Localizable.xcstrings"
            catalog_path.write_text(body, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--sources", str(sources), "--catalog", str(catalog_path)],
                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("yinelenen", result.stderr)

    def test_raw_strings_do_not_start_comments_and_keep_keys(self):
        swift = "\n".join([
            'let a = #"http://x // not a comment"#; Text("a")',
            'let b = ##"quote " and "# inside // still string"##; Text("b")',
            'let c = String(localized: "k")',
            'let d = #"""',
            '  // raw multi-line "',
            '"""#; Text("d")',
        ])
        result = self.run_check(swift, {"k": ("K", "K")})
        self.assertNotEqual(result.returncode, 0)
        for line in (1, 2, 6):
            self.assertIn(f"View.swift:{line}:", result.stderr)

    def test_raw_string_interpolation_with_literal_is_code(self):
        result = self.run_check('let a = #"x \\#(f("y")) z"#; Text("a")', {})
        self.assertIn("View.swift:1:", result.stderr)

    def test_nested_block_comments(self):
        swift = "\n".join(['/* a /* Text("a") */ Text("b") */', 'Text("c")'])
        result = self.run_check(swift, {})
        self.assertIn("View.swift:2:", result.stderr)
        self.assertNotIn("View.swift:1:", result.stderr)

    def test_multiline_initializers_are_reported_at_their_start(self):
        swift = "\n".join(['Link(', '    "a", destination: u)', 'Text(', '  "b")'])
        result = self.run_check(swift, {})
        self.assertIn("View.swift:1:", result.stderr)
        self.assertIn("View.swift:3:", result.stderr)

    def test_sharelink_and_navigationlink_literals_are_reported(self):
        swift = "\n".join(['ShareLink("a", item: u)', 'NavigationLink("b") { X() }', 'NavigationLink(destination: X()) { Y() }'])
        result = self.run_check(swift, {})
        self.assertIn("View.swift:1:", result.stderr)
        self.assertIn("View.swift:2:", result.stderr)
        self.assertNotIn("View.swift:3:", result.stderr)

    def test_nested_duplicate_key_reports_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            sources = Path(tmp) / "src"
            sources.mkdir()
            (sources / "View.swift").write_text('let a = String(localized: "k")', encoding="utf-8")
            unit = '{"stringUnit": {"state": "translated", "value": "V"}}'
            body = ('{"sourceLanguage": "en", "strings": {"k": {"localizations": {"en": %s, "tr": %s, "tr": %s}}}}'
                    % (unit, unit, unit))
            catalog_path = Path(tmp) / "Localizable.xcstrings"
            catalog_path.write_text(body, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--sources", str(sources), "--catalog", str(catalog_path)],
                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("strings/k/localizations/tr", result.stderr)


if __name__ == "__main__":
    unittest.main()
