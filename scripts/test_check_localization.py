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


if __name__ == "__main__":
    unittest.main()
