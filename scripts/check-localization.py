#!/usr/bin/env python3
"""Checks the String Catalog against the app's Swift sources (stdlib only).

Rules (formerly LocalizationTests):
  1. the catalog's source language is English
  2. every key has a translated, non-empty en and tr value
  3. every String(localized:) key in the sources is in the catalog, and no catalog key is unused
  4. interpolations in String(localized:) are plain identifiers
  5. no string literal is passed to a view initializer, .help/.navigationTitle/.confirmationDialog/.alert,
     NSAlert messageText/informativeText or addButton(withTitle:); every match is reported with its line number
Usage: check-localization.py [--sources DIR] [--catalog FILE]
Exits non-zero and lists every violation on failure.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCES = ROOT / "SSHConfigManager"
DEFAULT_CATALOG = DEFAULT_SOURCES / "Shared/Localization/Localizable.xcstrings"

LOCALIZED = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')
SIMPLE_INTERPOLATION = re.compile(r'\\\([A-Za-z_][A-Za-z0-9_]*\)')
VIEW_LITERAL = re.compile(
    r'(\b(?:Text|Button|Label|Section|Toggle|TextField|Picker|Menu|LabeledContent|Window|MenuBarExtra'
    r'|ContentUnavailableView|ProgressView|Stepper)\(\s*"'
    r'|\.(?:help|navigationTitle|confirmationDialog|alert)\(\s*"'
    r'|\b(?:messageText|informativeText)\s*=\s*"'
    r'|addButton\(withTitle:\s*")'
)


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=DEFAULT_SOURCES)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    args = parser.parse_args()
    sources, catalog_path = args.sources, args.catalog
    errors: list[str] = []
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))

    if catalog.get("sourceLanguage") != "en":
        errors.append("catalog sourceLanguage is not en")

    entries = catalog.get("strings", {})
    if not entries:
        errors.append("catalog has no strings")
    for key, entry in entries.items():
        languages = entry.get("localizations", {})
        for language in ("en", "tr"):
            unit = languages.get(language, {}).get("stringUnit", {})
            if unit.get("state") != "translated":
                errors.append(f"{key} [{language}] çevrilmemiş")
            if not unit.get("value"):
                errors.append(f"{key} [{language}] boş")

    source_keys: set[str] = set()
    for path in sorted(sources.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for match in LOCALIZED.finditer(text):
            body = match.group(1)
            if "\\(" in SIMPLE_INTERPOLATION.sub("", body):
                errors.append(f"{path.name}: karmaşık interpolasyon: {body}")
            source_keys.add(SIMPLE_INTERPOLATION.sub("%@", body))
        for match in VIEW_LITERAL.finditer(text):
            errors.append(f"{path.name}:{line_of(text, match.start())}: görünüm başlatıcısında string literal")

    catalog_keys = set(entries)
    for key in sorted(source_keys - catalog_keys):
        errors.append(f"katalogda eksik: {key}")
    for key in sorted(catalog_keys - source_keys):
        errors.append(f"kullanılmayan: {key}")

    if errors:
        print("Localization check FAILED:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print(f"Localization check passed ({len(catalog_keys)} keys).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
