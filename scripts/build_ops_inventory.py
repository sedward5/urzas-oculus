#!/usr/bin/env python3
"""Build the public, read-only data inventory consumed by the /ops page."""
import argparse
import json
import os
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen
from urllib.parse import quote

import set_catalog

WORKFLOWS = ("discover-limited-sets.yml", "acquire-set-data-bundle.yml")
REPOSITORY = "sedward5/urzas-oculus"
UA = "UrzasOculus-OpsInventory/1.0"

def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}

def read_front_matter(path):
    """Read simple scalar keys from a Hugo front matter block without a YAML dependency."""
    try:
        content = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    match = re.match(r"^---\\s*\\n(.*?)\\n---", content, re.S)
    if not match:
        return {}
    values = {}
    for key in ("content_status", "evidence_path", "source_url"):
        found = re.search(rf"(?m)^{key}:\\s*['\\"]?([^'\\"]+)", match.group(1))
        if found:
            values[key] = found.group(1).strip()
    return values

def workflow_history(repository=None, token=None):
    """Return workflow-run metadata only; no user, secret, or analytics payloads."""
    repository = repository or os.environ.get("GITHUB_REPOSITORY", REPOSITORY)
    token = token or os.environ.get("GITHUB_TOKEN")
    if not token:
        return []
    runs = []
    for workflow in WORKFLOWS:
        url = f"https://api.github.com/repos/{repository}/actions/workflows/{workflow}/runs?per_page=5"
        request = Request(url, headers={"Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": UA})
        try:
            with urlopen(request, timeout=20) as response:
                payload = json.loads(response.read().decode("utf-8"))
            for run in payload.get("workflow_runs", []):
                runs.append({"workflow": workflow, "name": run.get("name"),
                    "run_number": run.get("run_number"), "status": run.get("status"),
                    "conclusion": run.get("conclusion"), "created_at": run.get("created_at"),
                    "updated_at": run.get("updated_at"), "html_url": run.get("html_url"),
                    "event": run.get("event")})
        except (OSError, URLError, ValueError) as error:
            runs.append({"workflow": workflow, "status": "unavailable", "note": str(error)[:200]})
    return sorted(runs, key=lambda item: item.get("created_at") or "", reverse=True)

def build_inventory(root, discovered=None, runs=None):
    root = Path(root)
    report = discovered if discovered is not None else set_catalog.discover(root)
    archetypes = read_json(root / "scripts" / "data" / "reviewed_archetypes.json").get("sets", {})
    for item in report.get("sets", []):
        code = item["code"].upper()
        set_root = root / "website" / "static" / "data" / "sets" / code
        manifest = read_json(set_root / "manifest.json")
        card_file = set_root / "scryfall" / f"{code.lower()}-cards.json"
        archetype = archetypes.get(code, {})
        page_path = root / "website" / "content" / "archetypes" / code.lower() / "_index.md"
        page_meta = read_front_matter(page_path)
        page_status = ("reviewed" if archetype else
            page_meta.get("content_status", "preliminary") if page_path.is_file() else "missing")
        evidence_path = page_meta.get("evidence_path")
        evidence = read_json(root / "website" / evidence_path) if evidence_path else {}
        evidence_images = evidence.get("overview_images") or []
        evidence_image = next((entry for entry in evidence_images if entry.get("url")), {})
        image = archetype.get("overview_image") or {}
        image_url = image.get("source_url") or evidence_image.get("url")
        guide = archetype.get("source_url") or evidence.get("source_url") or page_meta.get("source_url")
        scryfall_records = sum(
            int(entry.get("records", 0)) for entry in manifest.get("files", [])
            if "scryfall" in entry.get("path", "").lower() and entry.get("records") is not None
        )
        item["acquisition"] = {
            "status": manifest.get("status", {}).get("scryfall", "not_run"),
            "generated_at": manifest.get("generated_at"),
            "manifest_present": bool(manifest),
            "card_file_present": card_file.is_file(),
            "card_record_count": scryfall_records or None,
            "manifest_status": manifest.get("status", {})
        }
        item["archetype_page"] = {
            "status": page_status,
            "url": f"/archetypes/{code.lower()}/" if page_path.is_file() else None
        }
        item["archetype_image"] = {
            "status": "present" if image_url else "missing",
            "url": image_url,
            "review_status": image.get("review_status") or evidence.get("review_status")
        }
        guide_status = ("found_in_reviewed_catalog" if archetype.get("source_url") else
            "found_in_acquisition_evidence" if evidence.get("source_url") else
            "found_on_archetype_page" if page_meta.get("source_url") else "search_available")
        item["wizards_guide"] = {
            "status": guide_status,
            "url": guide or f"https://magic.wizards.com/en/search?search={quote(item['name'] + ' prerelease guide')}"
        }
        prediction_dir = root / "website" / "static" / "data" / "predictions" / code
        prediction_files = sorted(str(path.relative_to(root)) for path in prediction_dir.glob("*.json")) if prediction_dir.is_dir() else []
        item["prediction"] = {"status": "available" if prediction_files else "not_run",
            "artifacts": prediction_files}
        for event in item.get("17lands", []):
            local_dir = root / "website" / "static" / "data" / "17lands" / code / event["event_type"]
            event_manifest = read_json(local_dir / "manifest.json")
            if not event_manifest and manifest.get("event_type") == event["event_type"]:
                event_manifest = manifest
            local = sorted(path.name for path in local_dir.glob("*.csv.gz")) if local_dir.is_dir() else []
            event["local_archives"] = local
            raw_date = (event.get("last_updated") or "")[:10]
            try:
                updated = date.fromisoformat(raw_date)
                event["last_updated_date"] = updated.isoformat()
                event["days_since_update"] = (datetime.now(timezone.utc).date() - updated).days
            except ValueError:
                event["last_updated_date"] = None
                event["days_since_update"] = None
            acquired_at = event_manifest.get("generated_at")
            acquired_date = acquired_at[:10] if acquired_at else None
            source_is_newer = bool(event["last_updated_date"] and acquired_date
                and event["last_updated_date"] > acquired_date)
            refresh_recommended = bool(event.get("archives") and (not local or not acquired_at or source_is_newer))
            event["local_acquired_at"] = acquired_at
            event["refresh_recommended"] = refresh_recommended
            event["refresh_reason"] = ("no local archive" if not local else
                "source listing is newer than the local acquisition" if source_is_newer else
                "acquisition time is not recorded for this event" if not acquired_at else "local archive appears current")
    report["schema_version"] = 2
    report["workflow_runs"] = runs if runs is not None else workflow_history()
    report["workflow_urls"] = {
        "discovery": "https://github.com/sedward5/urzas-oculus/actions/workflows/discover-limited-sets.yml",
        "acquisition": "https://github.com/sedward5/urzas-oculus/actions/workflows/acquire-set-data-bundle.yml"
    }
    return report

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, default=Path("website/static/data/ops/limited-sets.json"))
    parser.add_argument("--discovery", type=Path, help="Reuse a report produced by set_catalog.py discover")
    args = parser.parse_args()
    discovered = read_json(args.discovery) if args.discovery else None
    report = build_inventory(args.root, discovered=discovered)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Published operations inventory for {len(report.get('sets', []))} Limited sets.")

if __name__ == "__main__":
    main()
