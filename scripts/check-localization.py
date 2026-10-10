#!/usr/bin/env python3
"""Checks the String Catalog against the app's Swift sources (stdlib only).

Rules (formerly LocalizationTests):
  1. the catalog's source language is English
  2. every key has a translated, non-empty en and tr value
  3. every String(localized:) key in the sources is in the catalog, and no catalog key is unused
  4. interpolations in String(localized:) are plain identifiers
  5. no string literal is passed to a view initializer, .help/.navigationTitle/.confirmationDialog/.alert,
     NSAlert messageText/informativeText or addButton(withTitle:), .accessibilityLabel, Link or NSMenuItem(title:);
     every match is reported with its line number; matches inside comments are ignored
  6. the catalog has no duplicate keys (at any level; reported with the JSON path)
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
    r'|ContentUnavailableView|ProgressView|Stepper|ShareLink|NavigationLink)\(\s*"'
    r'|\.(?:help|navigationTitle|confirmationDialog|alert)\(\s*"'
    r'|\b(?:messageText|informativeText)\s*=\s*"'
    r'|addButton\(withTitle:\s*"'
    r'|\.accessibilityLabel\(\s*"'
    r'|\bLink\(\s*"'
    r'|\bNSMenuItem\(title:\s*")'
)


def strip_comments(text: str) -> str:
    """Blanks out // and /* */ comments (nested block comments too), keeping offsets and newlines.
    String literals are left intact (LOCALIZED needs them) and are skipped so "https://x" is not a comment."""
    out = list(text)
    i, n = 0, len(text)
    # stack of contexts: "code" or ("str", multiline) ; interpolation pushes "code" with paren depth
    stack: list = [["code", 0]]
    while i < n:
        top = stack[-1]
        c = text[i]
        if top[0] == "code":
            if text.startswith("//", i):
                while i < n and text[i] != "\n":
                    out[i] = " "
                    i += 1
                continue
            if text.startswith("/*", i):
                depth = 0
                while i < n:
                    if text.startswith("/*", i):
                        depth += 1
                        out[i] = out[i + 1] = " "
                        i += 2
                    elif text.startswith("*/", i):
                        depth -= 1
                        out[i] = out[i + 1] = " "
                        i += 2
                        if depth == 0:
                            break
                    else:
                        if text[i] != "\n":
                            out[i] = " "
                        i += 1
                continue
            if c == "#":
                j = i
                while j < n and text[j] == "#":
                    j += 1
                if j < n and text[j] == '"':
                    hashes = j - i
                    if text.startswith('"""', j):
                        stack.append(["str", True, hashes])
                        i = j + 3
                    else:
                        stack.append(["str", False, hashes])
                        i = j + 1
                    continue
                i = j
                continue
            if text.startswith('"""', i):
                stack.append(["str", True, 0])
                i += 3
                continue
            if c == '"':
                stack.append(["str", False, 0])
                i += 1
                continue
            if len(stack) > 1:  # inside an interpolation: track parens
                if c == "(":
                    top[1] += 1
                elif c == ")":
                    if top[1] == 0:
                        stack.pop()
                    else:
                        top[1] -= 1
            i += 1
        else:
            escape = "\\" + "#" * top[2]
            if text.startswith(escape, i) and i + len(escape) < n:
                if text[i + len(escape)] == "(":
                    stack.append(["code", 0])
                i += len(escape) + 1
                continue
            closer = ('"""' if top[1] else '"') + "#" * top[2]
            if text.startswith(closer, i):
                stack.pop()
                i += len(closer)
                continue
            if not top[1] and c == "\n":
                stack.pop()  # unterminated literal; recover
            i += 1
    return "".join(out)


class JSONObject(dict):
    duplicates: list

    def __init__(self):
        super().__init__()
        self.duplicates = []


def record_duplicates(pairs: list) -> JSONObject:
    seen = JSONObject()
    for key, value in pairs:
        if key in seen:
            seen.duplicates.append(key)
        seen[key] = value
    return seen


def find_duplicates(node, path: str = "") -> list[str]:
    """Every duplicated key with its JSON path (parent keys joined by '/')."""
    found: list[str] = []
    if isinstance(node, JSONObject):
        found += [f"{path}/{key}" if path else key for key in node.duplicates]
    if isinstance(node, dict):
        for key, value in node.items():
            found += find_duplicates(value, f"{path}/{key}" if path else key)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            found += find_duplicates(value, f"{path}[{index}]")
    return found


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=DEFAULT_SOURCES)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    args = parser.parse_args()
    sources, catalog_path = args.sources, args.catalog
    errors: list[str] = []
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"), object_pairs_hook=record_duplicates)
    for key in find_duplicates(catalog):
        errors.append(f"yinelenen katalog anahtarı: {key}")

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
        text = strip_comments(path.read_text(encoding="utf-8"))
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
