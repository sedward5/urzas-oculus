#!/usr/bin/env python3
"""Copy the canonical reviewed card catalog into website and app resources."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts/data/reviewed_cards.json"
TARGETS = (ROOT / "website/data/reviewed_cards.json", ROOT / "Sources/UrzasOculusApp/Resources/reviewed_cards.json")
def main():
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("sets"), dict):
        raise SystemExit("Unsupported reviewed card catalog schema")
    payload = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    for target in TARGETS:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(payload, encoding="utf-8")
        print(f"Synced {target.relative_to(ROOT)}")
if __name__ == "__main__":
    main()
