#!/usr/bin/env python3
"""Generate Hugo set pages from the human-reviewed archetype catalog."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "scripts" / "data" / "reviewed_archetypes.json"
DEST = ROOT / "website" / "content" / "archetypes"


def generate(catalog_path: Path = CATALOG, destination: Path = DEST) -> int:
    """Generate reviewed pages without deleting independently authored pages."""
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    sets = catalog.get("sets", {})
    destination.mkdir(parents=True, exist_ok=True)

    for code, record in sets.items():
        slug = code.lower()
        title = record.get("set_name", code)
        release_date = record.get("release_date")
        if not release_date:
            raise ValueError(f"{code} is missing its authoritative release_date")
        count = len(record.get("archetypes", []))
        description = (
            f"Human-reviewed Limited archetypes and card relationships for {title}. "
            f"Includes {count} reviewed archetype entries."
        )
        directory = destination / slug
        directory.mkdir(parents=True, exist_ok=True)
        content = (
            "---\n"
            f'title: "{title.replace(chr(34), chr(39))}"\n'
            f'description: "{description.replace(chr(34), chr(39))}"\n'
            f'set_code: "{code}"\n'
            f'release_date: "{release_date}"\n'
            'content_status: "reviewed"\n'
            'layout: "archetype-set"\n'
            "---\n"
        )
        (directory / "_index.md").write_text(content, encoding="utf-8")

    print(f"Generated {len(sets)} reviewed set pages; preserved other authored pages.")
    return len(sets)


def main() -> None:
    generate()


if __name__ == "__main__":
    main()
