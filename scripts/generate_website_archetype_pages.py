#!/usr/bin/env python3
"""Generate Hugo set pages from the human-reviewed archetype catalog."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "scripts" / "data" / "reviewed_archetypes.json"
DEST = ROOT / "website" / "content" / "archetypes"

def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    sets = catalog.get("sets", {})
    DEST.mkdir(parents=True, exist_ok=True)
    for code, record in sorted(sets.items()):
        slug = code.lower()
        title = record.get("set_name", code)
        count = len(record.get("archetypes", []))
        description = f"Human-reviewed Limited archetypes and card relationships for {title}. Includes {count} reviewed archetype entries."
        directory = DEST / slug
        directory.mkdir(parents=True, exist_ok=True)
        content = (
            "---\n"
            f'title: "{title.replace(chr(34), chr(39))}"\n'
            f'description: "{description.replace(chr(34), chr(39))}"\n'
            f'set_code: "{code}"\n'
            'layout: "archetype-set"\n'
            "---\n"
        )
        (directory / "_index.md").write_text(content, encoding="utf-8")
    active = {code.lower() for code in sets}
    for path in DEST.iterdir():
        if path.is_dir() and path.name not in active and (path / "_index.md").exists():
            (path / "_index.md").unlink()
            try:
                path.rmdir()
            except OSError:
                pass
    print(f"Generated {len(sets)} reviewed set pages.")

if __name__ == "__main__":
    main()
