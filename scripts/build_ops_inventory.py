#!/usr/bin/env python3
"""Build the public, read-only data inventory consumed by the /ops page."""
import argparse
import json
import os
import re
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
        found = re.search(rf\'''(?m)^{key}:\\s*["']?([^"']+)\''', match.group(1))
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


def validated_archive_count(manifest):
    """Count only archives whose retained provenance records validation evidence."""
    archives = manifest.get("archives", {})
    return sum(
        1 for record in archives.values()
        if isinstance(record, dict)
        and record.get("sha256")
        and record.get("gzip_valid") is True
        and isinstance(record.get("bytes"), int)
        and record.get("bytes", 0) > 0
    )


def processed_data_status(event_root):
    """Validate the explicit processed-data manifest and each declared JSON artifact.

    Contract: processed/manifest.json contains an 'artifacts' array. Each item
    has a repository-relative-to-event-root 'path' and optional 'records'.
    Artifact paths may not escape the event directory. A manifest is the
    declaration of completeness; loose JSON files are not treated as products.
    """
    processed_root = event_root / "processed"
    manifest_path = processed_root / "manifest.json"
    if not manifest_path.is_file():
        return {"status": "not_generated", "artifacts": [], "artifact_count": 0,
                "invalid_artifacts": []}
    manifest = read_json(manifest_path)
    entries = manifest.get("artifacts")
    if not isinstance(entries, list) or not entries:
        return {"status": "invalid", "artifacts": [], "artifact_count": 0,
                "invalid_artifacts": ["processed/manifest.json: missing non-empty artifacts list"]}
    artifacts = []
    invalid = []
    base = event_root.resolve()
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            invalid.append("manifest entry missing path")
            continue
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            invalid.append(entry["path"] + ": unsafe path")
            continue
        path = (event_root / relative).resolve()
        if base not in path.parents:
            invalid.append(entry["path"] + ": path escapes event directory")
            continue
        if not path.is_file():
            invalid.append(entry["path"] + ": file missing")
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            invalid.append(entry["path"] + ": invalid JSON")
            continue
        artifacts.append(str(path.relative_to(event_root)))
    return {"status": "available" if not invalid else "invalid",
            "artifacts": artifacts, "artifact_count": len(artifacts),
            "invalid_artifacts": invalid}


def event_manifests(root, code):
    """Read retained per-event acquisition manifests, independent of catalog health."""
    event_root = root / "website" / "static" / "data" / "17lands" / code
    found = {}
    if not event_root.is_dir():
        return found
    for path in sorted(event_root.glob("*/manifest.json")):
        manifest = read_json(path)
        event_type = manifest.get("event_type") or path.parent.name
        if event_type:
            found[event_type] = (path.parent, manifest)
    return found


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
        item["prediction"] = {"status": "available" if prediction_files else "not_generated",
            "artifacts": prediction_files}

        # Merge public discovery with retained event manifests. The public
        # listing is optional and may be unavailable long after acquisition.
        discovered_events = {event["event_type"]: event for event in item.get("17lands", [])}
        retained_events = event_manifests(root, code)
        merged_events = []
        for event_type in sorted(set(discovered_events) | set(retained_events)):
            event = dict(discovered_events.get(event_type, {}))
            event_root, event_manifest = retained_events.get(event_type, (None, {}))
            event["event_type"] = event_type
            event["archives"] = event.get("archives") or event_manifest.get("archives", {})
            event["provenance_archive_count"] = validated_archive_count(event_manifest)
            event["local_raw_archive_count"] = (
                len(list(event_root.glob("*.csv.gz"))) if event_root and event_root.is_dir() else 0
            )
            event["processed_data"] = (
                processed_data_status(event_root) if event_root
                else {"status": "not_generated", "artifacts": [], "artifact_count": 0,
                      "invalid_artifacts": []}
            )
            event["local_acquired_at"] = event_manifest.get("generated_at")
            raw_date = (event.get("last_updated") or "")[:10]
            try:
                updated = date.fromisoformat(raw_date)
                event["last_updated_date"] = updated.isoformat()
                event["days_since_update"] = (datetime.now(timezone.utc).date() - updated).days
            except ValueError:
                event["last_updated_date"] = None
                event["days_since_update"] = None
            acquired_at = event.get("local_acquired_at")
            acquired_date = acquired_at[:10] if acquired_at else None
            source_is_newer = bool(event["last_updated_date"] and acquired_date
                and event["last_updated_date"] > acquired_date)
            has_source_listing = bool(event.get("archives"))
            refresh_recommended = bool(has_source_listing and (not acquired_at or source_is_newer))
            event["refresh_recommended"] = refresh_recommended
            event["refresh_reason"] = (
                "source listing is newer than the local acquisition" if source_is_newer else
                "no retained acquisition manifest" if has_source_listing and not acquired_at else
                "source listing unavailable; retained provenance preserved" if not has_source_listing and event_manifest else
                "source listing unavailable" if report.get("source_status", {}).get("17lands", {}).get("status") == "unavailable" else
                "local acquisition appears current" if acquired_at else "no source listing or acquisition manifest"
            )
            merged_events.append(event)
        item["17lands"] = merged_events
        if merged_events:
            statuses = [event["processed_data"]["status"] for event in merged_events]
            processed_status = ("available" if "available" in statuses else
                "invalid" if "invalid" in statuses else "not_generated")
        else:
            processed_status = "not_checked" if report.get("source_status", {}).get("17lands", {}).get("status") == "unavailable" else "not_listed"
        item["processed_data"] = {
            "status": processed_status,
            "artifact_count": sum(event["processed_data"]["artifact_count"] for event in merged_events),
            "artifacts": [
                f"{code}/{event['event_type']}/{artifact}"
                for event in merged_events for artifact in event["processed_data"]["artifacts"]
            ]
        }
        # Keep catalog health separate from retained acquisition evidence.
        if retained_events and not discovered_events:
            item["17lands_status"] = "catalog_unavailable_acquisition_retained" if report.get("source_status", {}).get("17lands", {}).get("status") == "unavailable" else "acquisition_manifest_present"
    report["schema_version"] = 3
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
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\\n", encoding="utf-8")
    print(f"Published operations inventory for {len(report.get('sets', []))} Limited sets.")


if __name__ == "__main__":
    main()
