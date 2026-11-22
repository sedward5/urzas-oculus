#!/usr/bin/env python3
"""Acquire Wizards-published Limited archetype evidence for manual review.

Reviewed taxonomy is maintained separately from article extraction. This script
preserves upstream evidence and never assigns signpost/supporting cards.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

EXTRACTOR_VERSION = "0.2.0"
SOURCES = {
    "HOB": {"name": "Magic: The Gathering | The Hobbit", "url": "https://magic.wizards.com/en/news/feature/the-hobbit-prerelease-guide"},
    "ECL": {"name": "Lorwyn Eclipsed", "url": "https://magic.wizards.com/en/news/feature/lorwyn-eclipsed-prerelease-guide"},
    "TDM": {"name": "Tarkir: Dragonstorm", "url": "https://magic.wizards.com/en/news/feature/tarkir-dragonstorm-prerelease-guide"},
}
CATALOG_PATH = Path(__file__).parent / "data" / "reviewed_archetypes.json"
COLOR_HEADING = re.compile(r"^(White|Blue|Black|Red|Green)[ -](White|Blue|Black|Red|Green)\s+(.+)$", re.IGNORECASE)


def clean(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


class ArticleParser(HTMLParser):
    """Dependency-free parser retaining article headings, paragraphs, and images."""

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
        self._in_title = False
        self._in_time = False
        self._article_depth = 0
        self._capture_article = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = dict(attrs)
        if tag == "title":
            self._in_title, self._buffer = True, []
        if tag == "time":
            self._in_time, self._buffer = True, []
            if attrs_map.get("datetime"):
                self.date_parts.append(attrs_map["datetime"] or "")
        if tag in {"article", "main"}:
            if not self._capture_article:
                self._capture_article, self._article_depth = True, 1
            else:
                self._article_depth += 1
        if tag in {"h1", "h2", "h3", "h4"}:
            self._tag, self._buffer = tag, []
        if tag == "p":
            self._paragraph = []
        if tag == "img":
            self.images.append({"alt": clean(attrs_map.get("alt") or ""),
                                "src": attrs_map.get("src") or attrs_map.get("data-src") or ""})

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
                self.headings.append({"level": self._tag, "text": heading})
            self._tag = None
        if tag == "p":
            paragraph = clean("".join(self._paragraph))
            if paragraph:
                self.paragraphs.append(paragraph)
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
    """Extract only explicit two-color headings; never promote arbitrary H3/H4s."""
    candidates = []
    color_map = {"white": "W", "blue": "U", "black": "B", "red": "R", "green": "G"}
    for heading in parser.headings:
        if heading["level"] not in {"h3", "h4"}:
            continue
        match = COLOR_HEADING.match(heading["text"])
        if not match:
            continue
        colors = "".join(c for c in "WUBRG" if c in {color_map[x.lower()] for x in match.groups()[:2]})
        candidates.append({
            "display_name": match.group(3).strip(),
            "heading_text": heading["text"],
            "published_color_identity": colors,
            "color_identity_status": "extracted_from_heading",
            "signpost_card_references": [],
            "supporting_card_references": [],
            "strategy_text": "",
            "evidence": [{"type": "heading", "value": heading["text"]}],
            "review_status": "needs_manual_review",
        })
    return candidates


def load_reviewed_catalog() -> dict:
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


def reviewed_candidates(set_code: str) -> list[dict]:
    set_record = load_reviewed_catalog()["sets"][set_code]
    return [{
        "id": item["id"],
        "display_name": item["display_name"],
        "heading_text": None,
        "published_color_identity": item["color_identity"],
        "color_identity_status": "manually_reviewed_from_official_overview",
        "archetype_type": item["archetype_type"],
        "signpost_card_references": [],
        "supporting_card_references": [],
        "strategy_text": item["strategy_text"],
        "evidence": [{
            "type": "official_overview_image_manual_review",
            "source_url": set_record["source_url"],
            "review_note": set_record["overview_image_review"],
        }],
        "review_status": "reviewed",
    } for item in set_record["archetypes"]]


def fetch_bytes(url: str, timeout: int = 30) -> bytes:
    request = Request(url, headers={"User-Agent": "UrzasOculusCatalogResearch/0.2 (+https://github.com/sedward5/urzas-oculus)"})
    with urlopen(request, timeout=timeout) as response:
        return response.read()


def acquire(set_code: str, output_dir: Path, html_override: Path | None = None) -> dict:
    source = SOURCES[set_code]
    retrieved_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    html_bytes = html_override.read_bytes() if html_override else fetch_bytes(source["url"])
    parser = ArticleParser()
    parser.feed(html_bytes.decode("utf-8", errors="replace"))
    observed_headings = extract_candidates(parser)
    taxonomy = load_reviewed_catalog()["sets"][set_code]
    candidates = reviewed_candidates(set_code)

    archetype_images = [item for item in parser.images if item["src"] and re.search(r"archetype|draft", item["alt"], re.IGNORECASE)]
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
                record.update({"download_status": "downloaded",
                               "local_path": str(Path("evidence") / set_code / filename),
                               "sha256": digest, "byte_length": len(image_bytes)})
            except (OSError, URLError, TimeoutError) as error:
                record.update({"download_status": "failed", "error": str(error)})

        image_records.append(record)

    card_refs = sorted(set(re.findall(r"\b\d{4}_MTG[A-Z0-9]+_(?:Main|ToknBstr):\s*[^\n<]+",
                                      html_bytes.decode("utf-8", errors="replace"))))
    article_text = "\n".join(parser.paragraphs)
    for candidate in candidates:
        candidate["evidence"].append({"type": "article_paragraphs_available", "paragraph_count": len(parser.paragraphs)})

    catalog = {
        "schema_version": 2,
        "extractor_version": EXTRACTOR_VERSION,
        "set_code": set_code,
        "set_name": source["name"],
        "source": {
            "publisher": "Wizards of the Coast", "url": source["url"],
            "article_title": parser.title_parts[0] if parser.title_parts else None,
            "publication_date": parser.date_parts[0] if parser.date_parts else None,
            "retrieved_at": retrieved_at, "html_sha256": hashlib.sha256(html_bytes).hexdigest(),
        },
        "taxonomy": {
            "status": taxonomy["taxonomy_status"],
            "dimensions": taxonomy["taxonomy_dimensions"],
            "review_method": load_reviewed_catalog()["review_method"],
            "source_overview_image_review": taxonomy["overview_image_review"],
        },
        "candidates": candidates,
        "observed_article_heading_candidates": observed_headings,
        "article_card_references_unassigned": card_refs,
        "overview_images": image_records,
        "review": {
            "status": "reviewed_taxonomy_with_unassigned_card_associations",
            "image_text_ocr": "not_performed",
            "image_color_symbol_extraction": "not_performed",
            "taxonomy_completeness": "manually_reviewed",
            "notes": [
                "Archetype names, color identities, and short strategy summaries were manually transcribed from the official overview image.",
                "TDM clan archetypes and secondary two-color themes are separate, intentionally overlapping taxonomy dimensions.",
                "Signpost and supporting card references remain unassigned.",
                "Article heading extraction is diagnostic only; it does not define the reviewed taxonomy.",
            ],
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / f"{set_code.lower()}-catalog-candidate.json").write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (output_dir / f"{set_code.lower()}-source-notes.md").write_text(render_notes(catalog, article_text), encoding="utf-8")
    return catalog


def render_notes(catalog: dict, article_text: str) -> str:
    lines = [
        f"# {catalog['set_name']} — published archetype catalog",
        "",
        f"- Source: {catalog['source']['url']}",
        f"- Article date: {catalog['source']['publication_date'] or 'not extracted'}",
        f"- Retrieved: {catalog['source']['retrieved_at']}",
        f"- HTML SHA-256: `{catalog['source']['html_sha256']}`",
        f"- Reviewed archetypes: {len(catalog['candidates'])}",
        f"- Taxonomy status: {catalog['taxonomy']['status']}",
        "",
        "## Reviewed archetypes", "",
    ]
    for item in catalog["candidates"]:
        lines.append(f"- **{item['display_name']}** — {item['published_color_identity']} ({item['archetype_type']}): {item['strategy_text']}")
    lines.extend(["", "## Article heading diagnostics", ""])
    if catalog["observed_article_heading_candidates"]:
        for item in catalog["observed_article_heading_candidates"]:
            lines.append(f"- {item['heading_text']} — diagnostic extraction only")
    else:
        lines.append("- No explicit two-color headings were detected.")
    lines.extend(["", "## Overview images", ""])
    for item in catalog["overview_images"]:
        lines.append(f"- {item['alt'] or 'Image without alt text'} — {item['download_status']}: {item.get('local_path', item['url'])}")
    if not catalog["overview_images"]:
        lines.append("- No image with an archetype/draft label was confidently identified.")
    lines.extend([
        "", "## Review boundaries", "",
        "- Names, color identities, and short strategy summaries were manually reviewed from the official overview image.",
        "- TDM three-color clans and two-color themes intentionally overlap; do not collapse them into one taxonomy.",
        "- Signpost and supporting card associations remain unassigned pending article-context review.",
        "- The article prose below is retained as source evidence, not automatically attributed to an archetype.",
        "", "## Article prose available to reviewer", "",
        article_text[:12000] if article_text else "_No paragraph text was extracted._", "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set-code", required=True, choices=sorted(SOURCES))
    parser.add_argument("--output-dir", type=Path, default=Path("published-archetype-output"))
    parser.add_argument("--html-fixture", type=Path, help="Use local HTML instead of fetching the official page (tests only).")
    args = parser.parse_args()
    result = acquire(args.set_code, args.output_dir, args.html_fixture)
    print(json.dumps({"set_code": args.set_code, "candidate_count": len(result["candidates"]),
                      "observed_heading_candidate_count": len(result["observed_article_heading_candidates"]),
                      "overview_image_count": len(result["overview_images"]),
                      "review_status": result["review"]["status"]}, indent=2))


if __name__ == "__main__":
    main()
