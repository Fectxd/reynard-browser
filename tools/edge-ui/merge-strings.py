#!/usr/bin/env python3
"""Merge tools/edge-ui/strings.json into the app's Localizable.xcstrings.

Upstream updates Localizable.xcstrings constantly (new strings, translation
syncs), so carrying the Edge UI strings as a text patch would conflict on
almost every sync. Instead they are merged by key: Edge entries are added or
override the upstream entry with the same key, everything else is untouched.
Output keeps Xcode's formatting (2-space indent, " : " separators, no
trailing newline) so the resulting diff stays minimal.

Usage: merge-strings.py <strings.json> <Localizable.xcstrings>
"""
import json
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    overlay_path, catalog_path = sys.argv[1], sys.argv[2]
    with open(overlay_path, encoding="utf-8") as handle:
        overlay = json.load(handle)["strings"]
    with open(catalog_path, encoding="utf-8") as handle:
        catalog = json.load(handle)

    strings = catalog.setdefault("strings", {})
    added = sum(1 for key in overlay if key not in strings)
    strings.update(overlay)

    with open(catalog_path, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False))

    print(f"Merged {len(overlay)} Edge UI strings ({added} new) into {catalog_path}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
