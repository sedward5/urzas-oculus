#!/usr/bin/env python3
"""Read-only Limited set discovery and provenance-preserving set source acquisition."""
import argparse, gzip, hashlib, json, re, time
from datetime import date, datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote, urljoin, urlparse
from urllib.request import Request, urlopen

SETS_API="https://api.scryfall.com/sets"
CARDS_API="https://api.scryfall.com/cards/search"
LANDS="https://www.17lands.com/public_datasets"
# The public catalog is a normal HTML page. A browser-like identity avoids
# presenting this read-only bulk-data request as an unidentified script client.
UA=("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
LIMITED={"expansion","core","masters","draft_innovation"}
EVENTS={"PremierDraft","TradDraft","PickTwoDraft","Sealed","TradSealed"}

def fetch(url,timeout=90):
    headers={"User-Agent":UA,"Accept":"application/json, text/html, */*"}
    if url==LANDS:
        headers.update({
            "Accept-Language":"en-US,en;q=0.9",
            "Referer":"https://www.17lands.com/",
            "Sec-Fetch-Dest":"document",
            "Sec-Fetch-Mode":"navigate",
            "Sec-Fetch-Site":"same-origin",
        })
    req=Request(url,headers=headers)
    with urlopen(req,timeout=timeout) as r:
        if r.status!=200: raise RuntimeError(f"HTTP {r.status}: {url}")
        return r.read()

def fetch_json(url):
    return json.loads(fetch(url).decode("utf-8"))

def clean(v): return re.sub(r"\s+"," ",v or "").strip()


def candidate_archive_url(kind, code, event):
    """Build a convention-derived public archive URL; availability must be verified."""
    if kind not in {"draft", "game", "replay"}:
        raise ValueError(f"Unsupported 17Lands archive kind: {kind}")
    if not re.fullmatch(r"[A-Z0-9]{2,6}", code.upper()):
        raise ValueError("Invalid set code for 17Lands candidate URL")
    if event not in EVENTS:
        raise ValueError("Unsupported event type for 17Lands candidate URL")
    return (f"https://data.17landscapes.com/analysis_data/{kind}_data/"
            f"{kind}_data_public.{code.upper()}.{event}.csv.gz")


def probe_candidate_url(url):
    """Check a candidate with a tiny GET; never treat a constructed URL as available."""
    req=Request(url,headers={"User-Agent":UA,"Accept":"application/gzip, application/octet-stream, */*",
                             "Range":"bytes=0-1"})
    try:
        with urlopen(req,timeout=30) as response:
            magic=response.read(2)
            if magic == bytes((31, 139)):
                return {"status":"available","http_status":response.status}
            return {"status":"invalid_response","http_status":response.status}
    except Exception as exc:
        status=getattr(exc,"code",None)
        if status in {404,410}:
            return {"status":"url_not_available","http_status":status}
        return {"status":"probe_failed","error_type":type(exc).__name__,
                "error":clean(str(exc))[:300]}

class LandsParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True); self.rows=[]; self.row=None; self.cell=None; self.links=[]
    def handle_starttag(self,t,a):
        a=dict(a)
        if t=="tr": self.row=[]
        elif t in {"td","th"} and self.row is not None: self.cell={"text":"","links":[]}
        elif t=="a" and a.get("href"):
            self.links.append(a["href"])
            if self.cell is not None: self.cell["links"].append(a["href"])
    def handle_data(self,d):
        if self.cell is not None: self.cell["text"]+=d
    def handle_endtag(self,t):
        if t in {"td","th"} and self.cell is not None and self.row is not None:
            self.row.append(self.cell); self.cell=None
        elif t=="tr" and self.row is not None:
            if self.row: self.rows.append(self.row)
            self.row=None

class GuideParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True); self.title=[]; self.headings=[]; self.paragraphs=[]; self.images=[]
        self.tag=None; self.buf=[]; self.p=None
    def handle_starttag(self,t,a):
        a=dict(a)
        if t=="title" or t in {"h1","h2","h3","h4"}: self.tag=t; self.buf=[]
        if t=="p": self.p=[]
        if t=="img" and (a.get("src") or a.get("data-src")): self.images.append({"alt":a.get("alt") or "","src":a.get("src") or a.get("data-src")})
    def handle_data(self,d):
        if self.tag: self.buf.append(d)
        if self.p is not None: self.p.append(d)
    def handle_endtag(self,t):
        if self.tag==t:
            value=clean("".join(self.buf))
            if t=="title": self.title.append(value)
            else: self.headings.append({"level":t,"text":value})
            self.tag=None
        if t=="p" and self.p is not None:
            value=clean("".join(self.p))
            if value: self.paragraphs.append(value)
            self.p=None

def parse_lands(raw):
    """Parse the public listing without depending on its presentation markup.

    17Lands has changed the page's table/layout markup over time. Archive
    filenames are self-describing, so collect trusted S3 links globally and
    use table rows only as an optional source for last-updated metadata.
    """
    p=LandsParser(); p.feed(raw); grouped={}
    for row in p.rows:
        if len(row)<3: continue
        code,event,updated=(clean(c["text"]) for c in row[:3])
        if code and event and re.fullmatch(r"[A-Za-z0-9 ]+",code):
            grouped[(code.upper(),event)]={"set_code":code.upper(),"event_type":event,
                "last_updated":updated,"archives":{}}
    trusted=0
    for href in p.links:
        u=urljoin(LANDS,href); parsed=urlparse(u)
        if parsed.scheme!="https" or parsed.hostname!="17lands-public.s3.amazonaws.com": continue
        name=parsed.path.rsplit("/",1)[-1]
        match=re.fullmatch(r"(draft|game|replay)_data_public\.([A-Za-z0-9]+)\.([A-Za-z0-9_-]+)\.csv\.gz",name,re.I)
        if not match: continue
        kind,code,event=match.groups(); key=(code.upper(),event)
        record=grouped.setdefault(key,{"set_code":code.upper(),"event_type":event,
            "last_updated":None,"archives":{}})
        record["archives"][kind.lower()]=u
    result=[row for row in grouped.values() if row["archives"]]
    if not result:
        preview=clean(raw[:500])
        raise ValueError(
            "17Lands listing contained no recognizable trusted S3 archive links "
            f"(response bytes: {len(raw.encode('utf-8',errors='replace'))}). "
            f"The response may be an access-denied page or changed markup. Preview: {preview!r}"
        )
    return sorted(result,key=lambda row:(row["set_code"],row["event_type"]))

def local_catalogs(root):
    result={}
    for filename,layer in (("reviewed_archetypes.json","archetypes"),("reviewed_cards.json","cards")):
        data=json.loads((root/"scripts"/"data"/filename).read_text(encoding="utf-8"))
        for code in data.get("sets",{}): result.setdefault(code.upper(),set()).add(layer)
    return result

def discover(root):
    now=datetime.now(timezone.utc); sets=json.loads(fetch(SETS_API))["data"]
    sets=[s for s in sets if s.get("set_type") in LIMITED and s.get("released_at") and s.get("digital") is not True]
    # 17Lands publication discovery is optional. Keep Scryfall set discovery
    # usable when the public listing is unavailable, challenged, or changes markup.
    # The parser itself still fails closed; only this orchestration boundary degrades.
    lands_status={"status":"available","retrieved_at":now.isoformat(),"error":None}
    try:
        rows=parse_lands(fetch(LANDS).decode("utf-8",errors="replace"))
    except (OSError, RuntimeError, ValueError, UnicodeError) as exc:
        rows=[]
        lands_status={"status":"unavailable","retrieved_at":now.isoformat(),
            "error_type":type(exc).__name__,
            "error":clean(str(exc))[:500]}
    by_set={}
    for row in rows: by_set.setdefault(row["set_code"],[]).append(row)
    local=local_catalogs(root); records=[]
    for s in sorted(sets,key=lambda x:(x["released_at"],x["code"]),reverse=True):
        code=s["code"].upper(); age=(now.date()-date.fromisoformat(s["released_at"])).days
        events=by_set.get(code,[]); layers=local.get(code,set())
        candidates={}
        if not events or lands_status["status"]=="unavailable":
            for kind in ("draft","game"):
                url=candidate_archive_url(kind,code,"PremierDraft")
                candidates[kind]={"url":url,**probe_candidate_url(url)}
        records.append({"code":code,"name":s["name"],"released_at":s["released_at"],"set_type":s["set_type"],
          "card_count":s.get("card_count"),"age_days":age,"17lands":events,
          "17lands_candidates":candidates,
          "17lands_status":("available" if events else ("candidate_url_available" if any(v.get("status")=="available" for v in candidates.values()) else
              ("url_not_available" if candidates and all(v.get("status")=="url_not_available" for v in candidates.values()) else
               ("unavailable" if lands_status["status"]=="unavailable" and not any(v.get("status")=="available" for v in candidates.values()) else
                ("awaiting_expected_publication" if age<35 else "not_listed"))))),
          "local_archetypes":"present" if "archetypes" in layers else "missing",
          "local_reviewed_cards":"present" if "cards" in layers else "missing"})
    return {"schema_version":1,"generated_at":now.isoformat(),"sets":records,
      "sources":{"scryfall":SETS_API,"17lands":LANDS},
      "source_status":{"scryfall":{"status":"available","retrieved_at":now.isoformat()},
          "17lands":lands_status},
      "17lands_publication_guidance":{"draft_days":14,"game_days":21,"replay_days":35,
        "note":"17Lands stated intentions, not guaranteed dates."}}

def guide_slug(set_name):
    """Create the conventional DailyMTG prerelease-guide slug from a Scryfall set name."""
    value=clean(set_name).lower()
    value=re.sub(r"^magic\s*:\s*the\s*gathering\s*[|—–:-]*\s*", "", value)
    value=re.sub(r"[^a-z0-9]+","-",value).strip("-")
    return f"{value}-prerelease-guide" if value else ""


def discover_guide(set_name):
    """Resolve the conventional official Wizards guide URL and verify its article title."""
    slug=guide_slug(set_name)
    if not slug: return None, "not_found"
    url=f"https://magic.wizards.com/en/news/feature/{slug}"
    try:
        raw=fetch(url)
    except (OSError, RuntimeError, ValueError):
        return None, "not_found"
    parser=GuideParser()
    parser.feed(raw.decode("utf-8",errors="replace"))
    title=clean(parser.title[0] if parser.title else "")
    title_words=set(re.findall(r"[a-z0-9]+",title.lower()))
    expected=[word for word in re.findall(r"[a-z0-9]+",clean(set_name).lower())
              if word not in {"magic","the","gathering","universes","beyond"}]
    if "prerelease" not in title_words or "guide" not in title_words or not expected or not all(word in title_words for word in expected):
        return None, "title_mismatch"
    return url, "discovered"


def download_archive(url,path):
    """Stream a catalog-listed public archive to disk and validate its gzip CRC."""
    path.parent.mkdir(parents=True,exist_ok=True)
    digest=hashlib.sha256(); size=0
    req=Request(url,headers={"User-Agent":UA,"Accept":"application/gzip, application/octet-stream, */*"})
    try:
        with urlopen(req,timeout=240) as response, path.open("wb") as output:
            while True:
                chunk=response.read(1024*1024)
                if not chunk: break
                output.write(chunk); digest.update(chunk); size+=len(chunk)
        physical_lines=0
        with gzip.open(path,"rb") as archive:
            while True:
                chunk=archive.read(1024*1024)
                if not chunk: break
                physical_lines += chunk.count(b"\n")
        return {"url":url,"path":str(path),"bytes":size,"sha256":digest.hexdigest(),
                "physical_lines":physical_lines,"gzip_valid":True}
    except Exception:
        path.unlink(missing_ok=True)
        raise


def save(url,path):
    data=fetch(url,timeout=240); path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(data)
    return {"url":url,"path":str(path),"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest()}

def acquire(code,event,guide,out):
    code=code.upper()
    if not re.fullmatch(r"[A-Z0-9]{2,6}",code): raise ValueError("Invalid set code")
    if event not in EVENTS: raise ValueError("Unsupported event type")
    if guide and not guide.startswith("https://magic.wizards.com/"): raise ValueError("Guide URL must use magic.wizards.com over HTTPS")
    out.mkdir(parents=True,exist_ok=True); now=datetime.now(timezone.utc).isoformat()
    manifest={"schema_version":1,"set_code":code,"event_type":event,"generated_at":now,"files":[],"status":{}}
    # Scryfall metadata includes image URIs; image binaries are not downloaded.
    url=f"{CARDS_API}?q={quote(f'set:{code} lang:en')}&unique=cards&order=set"; cards=[]
    while url:
        page=json.loads(fetch(url)); cards.extend(page.get("data",[])); url=page.get("next_page")
        if url: time.sleep(1)
    if not cards: raise RuntimeError(f"Scryfall returned no English cards for {code}")
    cp=out/"scryfall"/f"{code.lower()}-cards.json"; cp.parent.mkdir(parents=True,exist_ok=True)
    cp.write_text(json.dumps({"set_code":code,"retrieved_at":now,"source":CARDS_API,"cards":cards},indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    manifest["files"].append({"path":str(cp),"bytes":cp.stat().st_size,"sha256":hashlib.sha256(cp.read_bytes()).hexdigest(),"records":len(cards)})
    manifest["status"]["scryfall"]="acquired"
    set_name=cards[0].get("set_name") or code
    manifest["set_name"]=set_name
    guide_discovery="provided" if guide else "not_attempted"
    if not guide:
        guide,guide_discovery=discover_guide(set_name)
    manifest["wizards_guide"]={"url":guide,"discovery":guide_discovery}
    # Resolve exact public archive URLs from 17Lands' catalog. Do not guess
    # S3 keys or treat a HEAD response as proof that an archive is unavailable.
    archives={}; probes={}; catalog_status="available"; catalog_last_updated=None
    catalog_error=None
    try:
        catalog_rows=parse_lands(fetch(LANDS).decode("utf-8",errors="replace"))
        listing=next((row for row in catalog_rows
                      if row["set_code"]==code and row["event_type"]==event),None)
        if listing:
            catalog_last_updated=listing.get("last_updated")
            for kind,url in listing.get("archives",{}).items():
                if kind not in {"draft","game","replay"}: continue
                try:
                    rec=download_archive(url,out/"17lands"/f"{kind}.csv.gz")
                    archives[kind]=rec; manifest["files"].append(rec); probes[kind]="acquired"
                except Exception as exc:
                    probes[kind]="download_failed"
                    manifest.setdefault("warnings",[]).append(
                        f"17Lands {kind} archive download failed: {type(exc).__name__}: {clean(str(exc))[:300]}")
            for kind in ("draft","game","replay"):
                if kind not in listing["archives"]: probes[kind]="not_listed"
        else:
            catalog_status="set_event_not_listed"
            probes={kind:"not_listed" for kind in ("draft","game","replay")}
    except (OSError,RuntimeError,ValueError,UnicodeError) as exc:
        catalog_status="unavailable"
        catalog_error={"type":type(exc).__name__,"message":clean(str(exc))[:800]}
        probes={kind:"catalog_unavailable" for kind in ("draft","game","replay")}
    candidate_urls={}
    for kind in ("draft","game"):
        if kind in archives:
            continue
        candidate=candidate_archive_url(kind,code,event)
        candidate_urls[kind]=candidate
        try:
            rec=download_archive(candidate,out/"17lands"/f"{kind}.csv.gz")
            archives[kind]=rec; manifest["files"].append(rec); probes[kind]="acquired"
        except Exception as exc:
            if getattr(exc,"code",None) in {404,410}:
                probes[kind]="url_not_available"
            else:
                probes[kind]="download_failed"
                manifest.setdefault("warnings",[]).append(
                    f"17Lands {kind} convention URL could not be acquired: {type(exc).__name__}: {clean(str(exc))[:300]}")
    # Replay is optional and this fallback intentionally targets only draft/game archives.\n    if probes.get("replay")=="catalog_unavailable":\n        probes["replay"]="not_checked"\n    manifest["17lands"]={"event_type":event,"catalog_url":LANDS,
        "candidate_urls":candidate_urls,
        "catalog_status":catalog_status,"catalog_last_updated":catalog_last_updated,
        "catalog_error":catalog_error,"archives":archives,"probes":probes,
        "source_selection":{"bulk_available":sorted(archives),
            "bulk_missing":[kind for kind in ("draft","game") if kind not in archives]}}
    required=("game",) if event in {"Sealed","TradSealed"} else ("draft","game")
    if all(probes.get(kind)=="acquired" for kind in required) and all(probes.get(kind) in {"acquired","not_listed","not_checked"} for kind in ("draft","game","replay")): lands_status="acquired"
    elif archives: lands_status="partially_acquired"
    elif "download_failed" in probes.values(): lands_status="download_failed"
    elif all(probes.get(kind)=="url_not_available" for kind in required): lands_status="url_not_available"
    elif catalog_status=="set_event_not_listed": lands_status="not_listed"
    elif catalog_status=="unavailable": lands_status="unavailable"
    else: lands_status="not_yet_published"
    manifest["status"]["17lands"]=lands_status
    if guide:
        if not guide.startswith("https://magic.wizards.com/"): raise ValueError("Guide URL must use magic.wizards.com over HTTPS")
        raw=fetch(guide); p=GuideParser(); p.feed(raw.decode("utf-8",errors="replace"))
        wd=out/"wizards"; wd.mkdir(parents=True,exist_ok=True); hp=wd/"guide.html"; hp.write_bytes(raw)
        imgs=[]
        for i,img in enumerate(p.images,1):
            if not re.search(r"archetype|draft",img["alt"],re.I): continue
            u=urljoin(guide,img["src"]); host=urlparse(u).hostname or ""
            if urlparse(u).scheme!="https" or not (host=="wizards.com" or host.endswith(".wizards.com")):
                imgs.append({"url":u,"alt":img["alt"],"error":"Image URL is outside the official Wizards HTTPS domain."})
                continue
            try:
                suffix=Path(u.split("?")[0]).suffix or ".img"; rec=save(u,wd/f"overview-{i}{suffix}")
                rec["alt"]=img["alt"]; imgs.append(rec); manifest["files"].append(rec)
            except Exception as e: imgs.append({"url":u,"alt":img["alt"],"error":str(e)})
        evidence={"set_code":code,"source_url":guide,"retrieved_at":now,"article_title":p.title[0] if p.title else None,
          "html_sha256":hashlib.sha256(raw).hexdigest(),"headings":p.headings,"paragraphs":p.paragraphs,
          "overview_images":imgs,"review_status":"source_evidence_only_not_reviewed"}
        ep=wd/"guide-evidence.json"; ep.write_text(json.dumps(evidence,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
        manifest["files"] += [{"path":str(hp),"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest()},
          {"path":str(ep),"bytes":ep.stat().st_size,"sha256":hashlib.sha256(ep.read_bytes()).hexdigest()}]
        manifest["status"]["wizards"]="evidence_acquired_unreviewed"
    else: manifest["status"]["wizards"]="not_found" if guide_discovery in {"not_found","title_mismatch"} else "not_requested"
    (out/"manifest.json").write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    lines=["# Set acquisition report","",f"Set: {code}",f"Event: {event}",f"Generated: {now}","","## Status"]
    lines += [f"- {k}: {v}" for k,v in manifest["status"].items()]
    lines += ["","## Promotion boundary","",
      "Candidate artifact only. Wizards evidence is unreviewed; archetypes and card relationships require human review.",
      "Scryfall metadata does not assign archetype roles. 17Lands archives still require metric processing and eligibility caveats.",
      "No canonical reviewed catalog, app resource, website data, or recommendation artifact was modified.",""]
    (out/"acquisition-report.md").write_text("\n".join(lines),encoding="utf-8")
    return manifest

def main():
    p=argparse.ArgumentParser(description=__doc__); sub=p.add_subparsers(dest="cmd",required=True)
    d=sub.add_parser("discover"); d.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[1]); d.add_argument("--output",type=Path,default=Path("set-discovery-output"))
    a=sub.add_parser("acquire"); a.add_argument("--set-code",required=True); a.add_argument("--event-type",default="PremierDraft",choices=sorted(EVENTS)); a.add_argument("--guide-url",default=""); a.add_argument("--output",type=Path,default=Path("set-acquisition-output"))
    x=p.parse_args()
    if x.cmd=="discover":
        report=discover(x.root); x.output.mkdir(parents=True,exist_ok=True)
        (x.output/"set-discovery.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
        lines=["# Limited set discovery","",f"Generated: {report['generated_at']}","","| Set | Release | Age | 17Lands | Archetypes | Cards |","|---|---:|---:|---|---|---|"]
        for s in report["sets"][:50]:
            ev="; ".join(f"{r['event_type']} [{', '.join(sorted(r['archives']))}] updated {r['last_updated']}" for r in s["17lands"]) or s["17lands_status"]
            lines.append(f"| {s['code']} — {s['name']} | {s['released_at']} | {s['age_days']}d | {ev} | {s['local_archetypes']} | {s['local_reviewed_cards']} |")
        lines += ["","17Lands publication guidance: draft ~14 days, game ~21 days, replay ~35 days after set start. These are expectations, not guarantees.",
          "Discovery is read-only. Missing local catalogs are gaps to review, not automatic errors.",""]
        (x.output/"set-discovery.md").write_text("\n".join(lines),encoding="utf-8")
        print(f"Discovered {len(report['sets'])} Limited sets.")
    else: print(json.dumps(acquire(x.set_code,x.event_type,x.guide_url,x.output)["status"],indent=2))
if __name__=="__main__": main()
