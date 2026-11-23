#!/usr/bin/env python3
"""Read-only Limited set discovery and provenance-preserving set source acquisition."""
import argparse, hashlib, json, re, time
from datetime import date, datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote, urljoin, urlparse
from urllib.request import Request, urlopen

SETS_API="https://api.scryfall.com/sets"
CARDS_API="https://api.scryfall.com/cards/search"
LANDS="https://www.17lands.com/public_datasets"
UA="UrzasOculus-SetCatalog/1.0 (+https://github.com/sedward5/urzas-oculus)"
LIMITED={"expansion","core","masters","draft_innovation"}
EVENTS={"PremierDraft","TradDraft","PickTwoDraft","Sealed","TradSealed"}

def fetch(url,timeout=90):
    req=Request(url,headers={"User-Agent":UA,"Accept":"application/json, text/html, */*"})
    with urlopen(req,timeout=timeout) as r:
        if r.status!=200: raise RuntimeError(f"HTTP {r.status}: {url}")
        return r.read()

def fetch_json(url):
    return json.loads(fetch(url).decode("utf-8"))

def clean(v): return re.sub(r"\s+"," ",v or "").strip()

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
        preview=clean(raw[:240])
        raise ValueError(
            "17Lands listing contained no recognizable trusted S3 archive links "
            f"(response bytes: {len(raw.encode('utf-8',errors='replace'))}). "
            f"The page markup may have changed or returned a challenge page. Preview: {preview!r}"
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
    rows=parse_lands(fetch(LANDS).decode("utf-8",errors="replace")); by_set={}
    for row in rows: by_set.setdefault(row["set_code"],[]).append(row)
    local=local_catalogs(root); records=[]
    for s in sorted(sets,key=lambda x:(x["released_at"],x["code"]),reverse=True):
        code=s["code"].upper(); age=(now.date()-date.fromisoformat(s["released_at"])).days
        events=by_set.get(code,[]); layers=local.get(code,set())
        records.append({"code":code,"name":s["name"],"released_at":s["released_at"],"set_type":s["set_type"],
          "card_count":s.get("card_count"),"age_days":age,"17lands":events,
          "17lands_status":"available" if events else ("awaiting_expected_publication" if age<35 else "not_listed"),
          "local_archetypes":"present" if "archetypes" in layers else "missing",
          "local_reviewed_cards":"present" if "cards" in layers else "missing"})
    return {"schema_version":1,"generated_at":now.isoformat(),"sets":records,
      "sources":{"scryfall":SETS_API,"17lands":LANDS},
      "17lands_publication_guidance":{"draft_days":14,"game_days":21,"replay_days":35,
        "note":"17Lands stated intentions, not guaranteed dates."}}

def save(url,path):
    data=fetch(url,timeout=240); path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(data)
    return {"url":url,"path":str(path),"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest()}

def archive_url(code,event,kind):
    """Build the public S3 object key for one set/event archive."""
    if kind not in {"draft","game","replay"}: raise ValueError(f"Unsupported archive kind: {kind}")
    return (f"https://17lands-public.s3.amazonaws.com/analysis_data/{kind}_data/"
            f"{kind}_data_public.{code}.{event}.csv.gz")

def probe_archive(url):
    """Check one known S3 object without scraping the 17Lands HTML listing."""
    req=Request(url,headers={"User-Agent":UA},method="HEAD")
    try:
        with urlopen(req,timeout=30) as response:
            return response.status == 200
    except Exception as exc:
        status=getattr(exc,"code",None)
        if status == 404: return False
        if status == 403:
            # S3 may return 403 for a missing key when bucket listing is private.
            # Treat it as unavailable for acquisition, but preserve the ambiguity.
            return None
        raise RuntimeError(f"Could not check 17Lands archive {url}: {exc}") from exc



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
    # Probe deterministic public S3 object keys. Acquisition must not depend
    # on scraping the public_datasets presentation page.
    archives={}; probes={}
    for kind in ("draft","game","replay"):
        u=archive_url(code,event,kind)
        exists=probe_archive(u)
        probes[kind]="available" if exists is True else ("not_found" if exists is False else "inaccessible_or_missing")
        if exists is True:
            rec=save(u,out/"17lands"/f"{kind}.csv.gz")
            archives[kind]=rec; manifest["files"].append(rec)
    ambiguous=[kind for kind,status in probes.items() if status=="inaccessible_or_missing"]
    if ambiguous:
        manifest.setdefault("warnings",[]).append(
            "S3 returned 403 for these keys; they may be missing or inaccessible: "+", ".join(ambiguous))
    manifest["17lands"]={"event_type":event,"archives":archives,"probes":probes,
        "source_selection":{"bulk_available":sorted(archives),
            "bulk_missing":[kind for kind in ("draft","game") if kind not in archives]}}
    manifest["status"]["17lands"]="acquired" if archives else "not_yet_published"
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
    else: manifest["status"]["wizards"]="not_requested"
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
