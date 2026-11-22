#!/usr/bin/env python3
"""Acquire Wizards-published Limited archetype evidence for manual review.

This is an evidence extractor, not an OCR system or an authoritative taxonomy
builder. It deliberately leaves image-only and ambiguous fields unresolved.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
from dataclasses import asdict, dataclass
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

EXTRACTOR_VERSION = "0.1.0"
SOURCES = {
    "HOB": {
        "name": "Magic: The Gathering | The Hobbit",
        "url": "https://magic.wizards.com/en/news/feature/the-hobbit-prerelease-guide",
    },
    "ECL": {
        "name": "Lorwyn Eclipsed",
        "url": "https://magic.wizards.com/en/news/feature/lorwyn-eclipsed-prerelease-guide",
    },
    "TDM": {
        "name": "Tarkir: Dragonstorm",
        "url": "https://magic.wizards.com/en/news/feature/tarkir-dragonstorm-prerelease-guide",
    },
}


def clean(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


class ArticleParser(HTMLParser):
    """Small dependency-free parser that retains article headings and evidence."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title_parts: list[str] = []
        self.date_parts: list[str] = []
        self.headings: list[dict] = []
        self.images: list[dict] = []
        self.paragraphs: list[str] = []
        self._tag: str | None = None
        self._buffer: list[str] = []
        self._paragraph: list[str] = []
        self._heading: dict | None = None
        self._in_title = False
        self._in_time = False
        self._article_depth = 0
        self._capture_article = False
        self._archetype_mode = False
        self._archetype_done = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = dict(attrs)
        if tag == "title":
            self._in_title = True
            self._buffer = []
        if tag == "time":
            self._in_time = True
            self._buffer = []
            if attrs_map.get("datetime"):
                self.date_parts.append(attrs_map["datetime"] or "")
        if tag in {"article", "main"} and not self._capture_article:
            self._capture_article = True
            self._article_depth = 1
        elif self._capture_article and tag in {"article", "main"}:
            self._article_depth += 1
        if tag in {"h1", "h2", "h3", "h4"}:
            self._tag = tag
            self._buffer = []
        if tag == "p":
            self._paragraph = []
        if tag == "img":
            self.images.append({
                "alt": clean(attrs_map.get("alt") or ""),
                "src": attrs_map.get("src") or attrs_map.get("data-src") or "",
            })

    def handle_endtag(self, tag: str) -> None:
        if tag == "title" and self._in_title:
            self.title_parts.append(clean("".join(self._buffer)))
            self._in_title = False
        if tag == "time" and self._in_time:
            if not self.date_parts:
                self.date_parts.append(clean("".join(self._buffer)))
            self._in_time = False
        if tag == self._tag and self._tag:
            heading = clean("".join(self._buffer))
            if heading:
                if self._archetype_mode and tag in {"h2", "h3"} and "archetype" not in heading.lower():
                    if tag == "h2":
                        self._archetype_done = True
                        self._archetype_mode = False
                self.headings.append({"level": tag, "text": heading})
                if "draft archetype" in heading.lower():
                    self._archetype_mode = True
            self._tag = None
        if tag == "p":
            text = clean("".join(self._paragraph))
            if text:
                self.paragraphs.append(text)
            self._paragraph = []
        if tag in {"article", "main"} and self._capture_article:
            self._article_depth -= 1
            if self._article_depth <= 0:
                self._capture_article = False

    def handle_data(self, data: str) -> None:
        if self._in_title or self._in_time or self._tag:
            self._buffer.append(data)
        if self._paragraph is not None:
            self._paragraph.append(data)


def extract_candidates(parser: ArticleParser) -> list[dict]:
    """Extract headings following the archetype section; preserve uncertainty."""
    start = next((i for i, h in enumerate(parser.headings)
                  if "draft archetype" in h["text"].lower()), None)
    if start is None:
        return []
    candidates = []
    for heading in parser.headings[start + 1:]:
        if heading["level"] == "h2":
            break
        if heading["level"] not in {"h3", "h4"}:
            continue
        match = re.match(
            r"^(White|Blue|Black|Red|Green)[ -](White|Blue|Black|Red|Green)\s+(.+)$",
            heading["text"], re.IGNORECASE,
        )
        colors = None
        name = heading["text"]
        if match:
            color_map = {"white": "W", "blue": "U", "black": "B", "red": "R", "green": "G"}
            colors = "".join(c for c in "WUBRG" if c in {color_map[x.lower()] for x in match.groups()[:2]})
            name = match.group(3).strip()
        candidates.append({
            "display_name": name,
            "heading_text": heading["text"],
            "published_color_identity": colors,
            "color_identity_status": "extracted_from_heading" if colors else "unresolved",
            "signpost_card_references": [],
            "supporting_card_references": [],
            "strategy_text": "",
            "evidence": [{"type": "heading", "value": heading["text"]}],
            "review_status": "needs_manual_review",
        })
    return candidates


def fetch_bytes(url: str, timeout: int = 30) -> bytes:
    request = Request(url, headers={"User-Agent": "UrzasOculusCatalogResearch/0.1 (+https://github.com/sedward5/urzas-oculus)"})
    with urlopen(request, timeout=timeout) as response:
        return response.read()


def acquire(set_code: str, output_dir: Path, html_override: Path | None = None) -> dict:
    source = SOURCES[set_code]
    retrieved_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    if html_override:
        html_bytes = html_override.read_bytes()
    else:
        html_bytes = fetch_bytes(source["url"])
    parser = ArticleParser()
    parser.feed(html_bytes.decode("utf-8", errors="replace"))
    candidates = extract_candidates(parser)

    archetype_images = [
        item for item in parser.images
        if item["src"] and re.search(r"archetype|draft", item["alt"], re.IGNORECASE)
    ]
    image_records = []
    image_dir = output_dir / "evidence" / set_code
    image_dir.mkdir(parents=True, exist_ok=True)
    for index, item in enumerate(archetype_images, start=1):
        image_url = urljoin(source["url"], item["src"])
        record = {"alt": item["alt"], "url": image_url, "download_status": "not_attempted"}
        if not html_override:
            try:
                image_bytes = fetch_bytes(image_url)
                digest = hashlib.sha256(image_bytes).hexdigest()
                suffix = Path(urlparse(image_url).path).suffix or ".img"
                filename = f"overview-{index}-{digest[:12]}{suffix}"
                (image_dir / filename).write_bytes(image_bytes)
                record.update({
                    "download_status": "downloaded",
                    "local_path": str(Path("evidence") / set_code / filename),
                    "sha256": digest,
                    "byte_length": len(image_bytes),
                })
            except (OSError, URLError, TimeoutError) as error:
                record.update({"download_status": "failed", "error": str(error)})
        image_records.append(record)

    # Card-number/name strings are retained as article evidence, not assigned
    # to archetypes until a human reviews their local context.
    card_refs = sorted(set(re.findall(
        r"\b\d{4}_MTG[A-Z0-9]+_(?:Main|ToknBstr):\s*[^\n<]+",
        html_bytes.decode("utf-8", errors="replace"),
    )))
    article_text = "\\n".join(parser.paragraphs)
    for candidate in candidates:
        # Conservative text association: no automated proximity guess. Human
        # review assigns paragraphs/cards to an archetype in a later step.
        candidate["strategy_text"] = ""
        candidate["evidence"].append({
            "type": "article_paragraphs_available",
            "paragraph_count": len(parser.paragraphs),
        })

    catalog = {
        "schema_version": 1,
        "extractor_version": EXTRACTOR_VERSION,
        "set_code": set_code,
        "set_name": source["name"],
        "source": {
            "publisher": "Wizards of the Coast",
            "url": source["url"],
            "article_title": parser.title_parts[0] if parser.title_parts else None,
            "publication_date": parser.date_parts[0] if parser.date_parts else None,
            "retrieved_at": retrieved_at,
            "html_sha256": hashlib.sha256(html_bytes).hexdigest(),
        },
        "candidates": candidates,
        "article_card_references_unassigned": card_refs,
        "overview_images": image_records,
        "review": {
            "status": "needs_manual_review",
            "image_text_ocr": "not_performed",
            "image_color_symbol_extraction": "not_performed",
            "taxonomy_completeness": "not_assessed",
            "notes": [
                "This output is an evidence bundle, not a verified archetype catalog.",
                "Overview-image text and mana symbols require manual review.",
                "Card references are intentionally unassigned to avoid false associations.",
                "No missing archetypes are inferred from the ten possible color pairs.",
            ],
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / f"{set_code.lower()}-catalog-candidate.json").write_text(
        json.dumps(catalog, indent=2, ensure_ascii=False) + "\\n", encoding="utf-8"
    )
    (output_dir / f"{set_code.lower()}-source-notes.md").write_text(
        render_notes(catalog, article_text), encoding="utf-8"
    )
    return catalog


def render_notes(catalog: dict, article_text: str) -> str:
    lines = [
        f"# {catalog['set_name']} — published archetype extraction",
        "",
        f"- Source: {catalog['source']['url']}",
        f"- Article date: {catalog['source']['publication_date'] or 'not extracted'}",
        f"- Retrieved: {catalog['source']['retrieved_at']}",
        f"- HTML SHA-256: `{catalog['source']['html_sha256']}`",
        f"- Extracted heading candidates: {len(catalog['candidates'])}",
        "",
        "## Candidate headings",
        "",
    ]
    for item in catalog["candidates"]:
        colors = item["published_color_identity"] or "UNRESOLVED"
        lines.append(f"- **{item['display_name']}** — {colors}; manual review required")
    lines.extend(["", "## Overview images", ""])
    if catalog["overview_images"]:
        for item in catalog["overview_images"]:
            lines.append(f"- {item['alt'] or 'Image without alt text'} — {item['download_status']}: {item.get('local_path', item['url'])}")
    else:
        lines.append("- No image with an archetype/draft label was confidently identified.")
    lines.extend([
        "",
        "## Review requirements",
        "",
        "- Compare candidate headings and taxonomy against the official article.",
        "- Inspect preserved overview image(s); transcribe image-only archetypes and strategy text.",
        "- Verify color identities from mana symbols, not guessed from strategy names.",
        "- Assign signpost and supporting cards only after checking article context.",
        "- Mark taxonomy completeness only after all source content has been reviewed.",
        "",
        "## Article prose available to reviewer",
        "",
        article_text[:12000] if article_text else "_No paragraph text was extracted._",
        "",
    ])
    return "\\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set-code", required=True, choices=sorted(SOURCES))
    parser.add_argument("--output-dir", type=Path, default=Path("published-archetype-output"))
    parser.add_argument("--html-fixture", type=Path, help="Use local HTML instead of fetching the official page (tests only).")
    args = parser.parse_args()
    result = acquire(args.set_code, args.output_dir, args.html_fixture)
    print(json.dumps({
        "set_code": args.set_code,
        "candidate_count": len(result["candidates"]),
        "overview_image_count": len(result["overview_images"]),
        "review_status": result["review"]["status"],
    }, indent=2))


if __name__ == "__main__":
    main()
