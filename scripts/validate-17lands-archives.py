#!/usr/bin/env python3
"""Independent, streaming reference implementation for 17Lands public CSV metrics."""
from __future__ import annotations
import argparse, csv, gzip, html, json, math, subprocess, sys, urllib.request
from collections import defaultdict
from html.parser import HTMLParser
from pathlib import Path

CATALOG = "https://www.17lands.com/public_datasets"
UA = "UrzasOculus-ArchiveValidation/1.0"

class CatalogParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], None, None
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "tr": self.row = []
        elif tag == "td" and self.row is not None: self.cell = {"text": "", "links": []}
        elif tag == "a" and self.cell is not None and attrs.get("href"):
            self.cell["links"].append(attrs["href"])
    def handle_data(self, data):
        if self.cell is not None: self.cell["text"] += data
    def handle_endtag(self, tag):
        if tag == "td" and self.cell is not None and self.row is not None:
            self.row.append(self.cell); self.cell = None
        elif tag == "tr" and self.row is not None:
            if self.row: self.rows.append(self.row)
            self.row = None

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=180) as response:
        if response.status != 200: raise RuntimeError(f"HTTP {response.status}: {url}")
        return response

def archives(set_code, event_type):
    parser = CatalogParser()
    with get(CATALOG) as response: parser.feed(response.read().decode("utf-8"))
    for row in parser.rows:
        if len(row) < 5: continue
        vals = [html.unescape(c["text"]).strip() for c in row]
        if vals[0].upper() != set_code.upper() or vals[1] != event_type: continue
        draft = next((u for c in row for u in c["links"] if "draft_data_public." in u), None)
        game = next((u for c in row for u in c["links"] if "game_data_public." in u), None)
        if draft and game: return draft, game, vals[2]
    raise RuntimeError(f"No complete archive for {set_code} {event_type}")

def download(url, path):
    with get(url) as response, path.open("wb") as out:
        while chunk := response.read(1024 * 1024): out.write(chunk)

def integer(value, name):
    value = value.strip()
    if not value: return 0
    try: n = int(value)
    except ValueError as exc: raise ValueError(f"{name}: invalid integer {value!r}") from exc
    if n < 0: raise ValueError(f"{name}: negative count {value!r}")
    return n

def boolean(value):
    value = value.strip().lower()
    if value in ("true", "1"): return True
    if value in ("false", "0"): return False
    raise ValueError(f"won: invalid boolean {value!r}")

def ratio(n, d): return n / d if d else None

def game_reference(path):
    sums = defaultdict(lambda: defaultdict(int)); rows = wins = 0
    with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f); header = next(reader); ix = {n:i for i,n in enumerate(header)}
        if len(ix) != len(header): raise ValueError("duplicate game CSV headers")
        if "won" not in ix: raise ValueError("missing game column: won")
        facets = ("opening_hand_", "drawn_", "tutored_", "deck_", "sideboard_")
        cards = defaultdict(dict)
        for i, name in enumerate(header):
            for facet in facets:
                if name.startswith(facet) and name[len(facet):]:
                    cards[name[len(facet):]][facet] = i; break
        if not cards: raise ValueError("no game card facet columns")
        for line, row in enumerate(reader, 2):
            if len(row) != len(header): raise ValueError(f"game row {line}: width mismatch")
            won = boolean(row[ix["won"]]); rows += 1; wins += int(won)
            for card, cols in cards.items():
                c = {k: integer(row[i], header[i]) for k,i in cols.items()}
                deck, sb = c.get("deck_",0), c.get("sideboard_",0)
                op, dr, tut = c.get("opening_hand_",0), c.get("drawn_",0), c.get("tutored_",0)
                t = sums[card]
                t["gp"] += deck; t["gpw"] += deck if won else 0
                t["md"] += deck; t["sb"] += sb
                t["gih"] += op+dr; t["gihw"] += op+dr if won else 0
                t["oh"] += op; t["ohw"] += op if won else 0
                t["drawn"] += dr; t["drawnw"] += dr if won else 0
                unseen = max(0, deck-op-dr-tut)
                t["gns"] += unseen; t["gnsw"] += unseen if won else 0
    result = {}
    for card,t in sums.items():
        result[card] = {
            "gamesPlayedCount":t["gp"], "gamesPlayedWinRate":ratio(t["gpw"],t["gp"]),
            "playRate":ratio(t["md"],t["md"]+t["sb"]),
            "gamesInHandCount":t["gih"], "gamesInHandWinRate":ratio(t["gihw"],t["gih"]),
            "openingHandCount":t["oh"], "openingHandWinRate":ratio(t["ohw"],t["oh"]),
            "drawnCount":t["drawn"], "drawnWinRate":ratio(t["drawnw"],t["drawn"]),
            "gamesNotSeenCount":t["gns"], "gamesNotSeenWinRate":ratio(t["gnsw"],t["gns"])
        }
    return rows, wins, result

def draft_reference(path):
    sums = defaultdict(lambda: defaultdict(int)); rows = 0
    current = None; lanes = defaultdict(dict)
    def flush():
        for lane in lanes.values():
            for card,(last,copies) in lane.items():
                sums[card]["seen"] += copies
                sums[card]["lastsum"] += last*copies
        lanes.clear()
    with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f); header = next(reader); ix = {n:i for i,n in enumerate(header)}
        if len(ix) != len(header): raise ValueError("duplicate draft CSV headers")
        for name in ("draft_id","pack_number","pick_number","pick"):
            if name not in ix: raise ValueError(f"missing draft column: {name}")
        cards = [(n[len("pack_card_"):],i) for i,n in enumerate(header)
                 if n.startswith("pack_card_") and n[len("pack_card_"):]]
        if not cards: raise ValueError("no draft pack_card columns")
        for line,row in enumerate(reader,2):
            if len(row) != len(header): raise ValueError(f"draft row {line}: width mismatch")
            draft = row[ix["draft_id"]].strip()
            pack = integer(row[ix["pack_number"]],"pack_number")
            pick = integer(row[ix["pick_number"]],"pick_number")
            if not draft or pack < 1 or pick < 1: raise ValueError(f"draft row {line}: invalid identity")
            key = (draft,pack)
            if current is not None and current != key: flush()
            current = key; lane = lanes[(pick-1)%8]
            for card,i in cards:
                count = integer(row[i],header[i])
                if count:
                    old = lane.get(card,(0,0)); lane[card] = (max(old[0],pick),max(old[1],count))
            picks = [row[ix["pick"]].strip()]
            if "pick_2" in ix: picks.append(row[ix["pick_2"]].strip())
            for card in picks:
                if not card: continue
                old = lane.get(card,(0,0)); lane[card] = (pick,max(old[1],1))
                sums[card]["picked"] += 1; sums[card]["taken"] += pick
            rows += 1
    flush()
    result = {card:{"seenCount":t["seen"],"averageLastSeen":ratio(t["lastsum"],t["seen"]),
                    "pickCount":t["picked"],"averageTakenAt":ratio(t["taken"],t["picked"])}
              for card,t in sums.items()}
    return rows,result

def compare(label, expected, actual_rows):
    actual = {r["cardName"]:r for r in actual_rows}; errors=[]
    if expected.keys() != actual.keys():
        errors.append(f"{label}: card key mismatch; reference={len(expected)}, Swift={len(actual)}")
    for card in expected.keys() & actual.keys():
        for field,value in expected[card].items():
            got = actual[card].get(field)
            if value is None or got is None:
                if value is not got: errors.append(f"{label} {card} {field}: {value} != {got}")
            elif not math.isclose(float(value),float(got),rel_tol=1e-10,abs_tol=1e-10):
                errors.append(f"{label} {card} {field}: {value} != {got}")
    return errors

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--set-code",default="HOB"); p.add_argument("--event-type",default="PremierDraft")
    p.add_argument("--output-dir",default="validation-output"); a=p.parse_args()
    out=Path(a.output_dir).resolve(); out.mkdir(parents=True,exist_ok=True)
    try:
        draft_url,game_url,updated=archives(a.set_code,a.event_type)
        game=out/"game.csv.gz"; draft=out/"draft.csv.gz"; probe=out/"swift-metrics.json"
        print(f"Downloading {a.set_code} {a.event_type} (catalog updated {updated})")
        download(game_url,game); download(draft_url,draft)
        root=Path(__file__).resolve().parents[1]
        subprocess.run(["swift","run","-c","release","SeventeenLandsArchiveProbe",
                        str(game),str(draft),str(probe)],cwd=root,check=True)
        swift=json.loads(probe.read_text())
        gr,gw,gm=game_reference(game); dr,dm=draft_reference(draft)
        errors=compare("game",gm,swift["gameMetrics"])+compare("draft",dm,swift["draftMetrics"])
        if (gr,gw)!=(swift["gameRows"],swift["gameWins"]):
            errors.append(f"overall game baseline mismatch: reference {gw}/{gr}, Swift {swift['gameWins']}/{swift['gameRows']}")
        if dr != swift["draftRows"]: errors.append(f"draft row count mismatch: {dr} != {swift['draftRows']}")
        lines=[f"# 17Lands validation — {a.set_code}",
               "",f"- Format: {a.event_type}",f"- Catalog updated: {updated}",
               f"- Game rows: {gr:,}; wins: {gw:,}; unweighted WR: {ratio(gw,gr):.4%}",
               f"- Game metric cards: {len(gm):,}",f"- Draft rows: {dr:,}",
               f"- Draft metric cards: {len(dm):,}",f"- Discrepancies: {len(errors):,}",""]
        if errors: lines += ["## Discrepancies",""]+[f"- {e}" for e in errors[:500]]
        else: lines += ["## Result","","Independent reference metrics match the Swift accumulators."]
        (out/"validation-report.md").write_text("\n".join(lines)+"\n")
        print("\\n".join(lines))
        return 1 if errors else 0
    except Exception as exc:
        message=f"Validation failed: {type(exc).__name__}: {exc}"
        (out/"validation-error.txt").write_text(message+"\n")
        print(message,file=sys.stderr); return 2

if __name__=="__main__": raise SystemExit(main())
