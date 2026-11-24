import sys, unittest
from unittest.mock import patch, MagicMock
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import set_catalog

class CatalogTests(unittest.TestCase):


    def test_17lands_catalog_request_uses_browser_headers(self):
        from unittest.mock import patch, MagicMock
        response=MagicMock()
        response.status=200
        response.__enter__.return_value=response
        response.read.return_value=b"<html></html>"
        with patch.object(set_catalog,"urlopen",return_value=response) as mocked:
            set_catalog.fetch(set_catalog.LANDS)
        request=mocked.call_args.args[0]
        self.assertIn("Mozilla/5.0",request.get_header("User-agent"))
        self.assertEqual(request.get_header("Accept-language"),"en-US,en;q=0.9")
        self.assertEqual(request.get_header("Referer"),"https://www.17lands.com/")
        self.assertEqual(request.get_header("Sec-fetch-mode"),"navigate")

    def test_catalog_discovery_includes_hob_ecl_and_tdm(self):
        html="""<table>
        <tr><td>HOB</td><td>PremierDraft</td><td>2026-08-30</td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.HOB.PremierDraft.csv.gz">draft</a></td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data/game_data_public.HOB.PremierDraft.csv.gz">game</a></td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/replay_data/replay_data_public.HOB.PremierDraft.csv.gz">replay</a></td></tr>
        <tr><td>ECL</td><td>PremierDraft</td><td>2026-02-08</td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.ECL.PremierDraft.csv.gz">draft</a></td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data/game_data_public.ECL.PremierDraft.csv.gz">game</a></td></tr>
        <tr><td>TDM</td><td>PremierDraft</td><td>2025-05-20</td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.TDM.PremierDraft.csv.gz">draft</a></td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data/game_data_public.TDM.PremierDraft.csv.gz">game</a></td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/replay_data/replay_data_public.TDM.PremierDraft.csv.gz">replay</a></td></tr>
        </table>"""
        rows=set_catalog.parse_lands(html)
        by_code={row["set_code"]:row for row in rows}
        self.assertEqual(set(by_code),{"HOB","ECL","TDM"})
        self.assertEqual(set(by_code["HOB"]["archives"]),{"draft","game","replay"})
        self.assertEqual(set(by_code["ECL"]["archives"]),{"draft","game"})
        self.assertEqual(set(by_code["TDM"]["archives"]),{"draft","game","replay"})

    def test_parse_17lands_links(self):
        html="""<table><tr><td>TRK</td><td>PremierDraft</td><td>2026-11-22</td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.TRK.PremierDraft.csv.gz">draft</a></td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data/game_data_public.TRK.PremierDraft.csv.gz">game</a></td></tr></table>"""
        rows=set_catalog.parse_lands(html)
        self.assertEqual(rows[0]["set_code"],"TRK")
        self.assertEqual(set(rows[0]["archives"]),{"draft","game"})
    def test_parse_archive_links_outside_table_markup(self):
        html="""<main><div><a href="https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.TRK.PremierDraft.csv.gz">draft</a></div>
        <div><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data/game_data_public.TRK.PremierDraft.csv.gz">game</a></div></main>"""
        rows=set_catalog.parse_lands(html)
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0]["set_code"],"TRK")
        self.assertEqual(rows[0]["last_updated"],None)
        self.assertEqual(set(rows[0]["archives"]),{"draft","game"})

    def test_reject_untrusted_archive_host(self):
        html="""<table><tr><td>TRK</td><td>PremierDraft</td><td>2026-11-22</td>
        <td><a href="https://example.com/draft_data_public.TRK.PremierDraft.csv.gz">draft</a></td></tr></table>"""
        with self.assertRaises(ValueError): set_catalog.parse_lands(html)
    def test_empty_listing_fails_closed(self):
        with self.assertRaises(ValueError): set_catalog.parse_lands("<html>maintenance</html>")

    def test_acquire_uses_catalog_urls_and_records_missing_replay(self):
        from tempfile import TemporaryDirectory
        import json
        cards={"data":[{"set_name":"The Hobbit","name":"Test Card"}]}
        html="""<table><tr><td>HOB</td><td>PremierDraft</td><td>2026-08-30</td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.HOB.PremierDraft.csv.gz">draft</a></td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data/game_data_public.HOB.PremierDraft.csv.gz">game</a></td></tr></table>"""
        def fake_fetch(url,timeout=90):
            if url.startswith(set_catalog.CARDS_API): return json.dumps(cards).encode()
            if url==set_catalog.LANDS: return html.encode()
            raise AssertionError(url)
        downloaded=[]
        def fake_download(url,path):
            downloaded.append(url)
            return {"url":url,"path":str(path),"bytes":12,"sha256":"abc","physical_lines":3,"gzip_valid":True}
        with TemporaryDirectory() as directory:
            with (
                patch.object(set_catalog,"fetch",side_effect=fake_fetch),
                patch.object(set_catalog,"download_archive",side_effect=fake_download),
                patch.object(set_catalog,"discover_guide",return_value=(None,"not_found")),
            ):
                result=set_catalog.acquire("HOB","PremierDraft","",Path(directory))
            self.assertEqual(set(downloaded),{
                "https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.HOB.PremierDraft.csv.gz",
                "https://17lands-public.s3.amazonaws.com/analysis_data/game_data/game_data_public.HOB.PremierDraft.csv.gz"})
            self.assertEqual(result["17lands"]["catalog_last_updated"],"2026-08-30")
            self.assertEqual(result["17lands"]["probes"]["replay"],"not_listed")
            self.assertEqual(result["status"]["17lands"],"acquired")

    def test_download_archive_validates_gzip_and_counts_physical_lines(self):
        import gzip
        from tempfile import TemporaryDirectory
        from io import BytesIO
        from unittest.mock import MagicMock
        payload=BytesIO()
        with gzip.GzipFile(fileobj=payload,mode="wb") as archive:
            archive.write(b"header\nrow1\nrow2\n")
        response=MagicMock()
        response.read=MagicMock(side_effect=[payload.getvalue(),b""])
        response.__enter__.return_value=response
        with TemporaryDirectory() as directory:
            with patch.object(set_catalog,"urlopen",return_value=response):
                result=set_catalog.download_archive("https://example.test/data.csv.gz",Path(directory)/"data.csv.gz")
            self.assertTrue(result["gzip_valid"])
            self.assertEqual(result["physical_lines"],3)

    def test_guide_slug_uses_set_name(self):
        self.assertEqual(set_catalog.guide_slug("Magic: The Gathering | Star Trek"),"star-trek-prerelease-guide")
        self.assertEqual(set_catalog.guide_slug("The Hobbit"),"the-hobbit-prerelease-guide")

    def test_discover_guide_validates_official_article_title(self):
        html=b"<html><title>Star Trek Prerelease Guide</title><h1>Star Trek Prerelease Guide</h1></html>"
        with patch.object(set_catalog,"fetch",return_value=html):
            url,status=set_catalog.discover_guide("Star Trek")
        self.assertEqual(url,"https://magic.wizards.com/en/news/feature/star-trek-prerelease-guide")
        self.assertEqual(status,"discovered")

    def test_discover_guide_rejects_wrong_article(self):
        html=b"<html><title>Another Set Prerelease Guide</title></html>"
        with patch.object(set_catalog,"fetch",return_value=html):
            url,status=set_catalog.discover_guide("Star Trek")
        self.assertIsNone(url)
        self.assertEqual(status,"title_mismatch")

    def test_discover_guide_tolerates_missing_article(self):
        with patch.object(set_catalog,"fetch",side_effect=RuntimeError("404")):
            url,status=set_catalog.discover_guide("Star Trek")
        self.assertIsNone(url)
        self.assertEqual(status,"not_found")

    def test_guide_domain_guard_runs_before_network(self):
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as d:
            with self.assertRaises(ValueError): set_catalog.acquire("TRK","PremierDraft","https://example.com/x",Path(d))

    def test_discovery_publishes_catalog_archive_inventory(self):
        import json
        from tempfile import TemporaryDirectory
        html="""<table><tr><td>HOB</td><td>PremierDraft</td><td>2026-08-30</td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.HOB.PremierDraft.csv.gz">draft</a></td>
        <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data/game_data_public.HOB.PremierDraft.csv.gz">game</a></td></tr></table>"""
        sets={"data":[{"code":"HOB","name":"The Hobbit","set_type":"expansion",
            "released_at":"2026-08-30","digital":False,"card_count":300}]}
        def fake_fetch(url,timeout=90):
            if url==set_catalog.SETS_API: return json.dumps(sets).encode()
            if url==set_catalog.LANDS: return html.encode()
            raise AssertionError(url)
        with TemporaryDirectory() as directory:
            root=Path(directory)
            (root/"scripts/data").mkdir(parents=True)
            (root/"scripts/data/reviewed_archetypes.json").write_text('{"sets":{}}')
            (root/"scripts/data/reviewed_cards.json").write_text('{"sets":{}}')
            with patch.object(set_catalog,"fetch",side_effect=fake_fetch):
                report=set_catalog.discover(root)
        self.assertEqual(report["source_status"]["17lands"]["status"],"available")
        self.assertEqual(report["sets"][0]["17lands_status"],"available")
        self.assertEqual(set(report["sets"][0]["17lands"][0]["archives"]),{"draft","game"})

    def test_discovery_degrades_when_17lands_returns_challenge_page(self):
        from tempfile import TemporaryDirectory
        from unittest.mock import patch
        import json
        scryfall={"data":[{"code":"TRK","name":"Star Trek","set_type":"expansion",
            "released_at":"2026-11-20","digital":False,"card_count":311}]}
        def fake_fetch(url, timeout=90):
            if url==set_catalog.SETS_API:
                return json.dumps(scryfall).encode()
            if url==set_catalog.LANDS:
                return b"<!doctype html><html><title>Access denied</title></html>"
            raise AssertionError(url)
        with TemporaryDirectory() as directory:
            root=Path(directory)
            (root/"scripts/data").mkdir(parents=True)
            (root/"scripts/data/reviewed_archetypes.json").write_text('{"sets":{}}')
            (root/"scripts/data/reviewed_cards.json").write_text('{"sets":{}}')
            with patch.object(set_catalog,"fetch",side_effect=fake_fetch):
                report=set_catalog.discover(root)
        self.assertEqual(len(report["sets"]),1)
        self.assertEqual(report["sets"][0]["code"],"TRK")
        self.assertEqual(report["sets"][0]["17lands_status"],"unavailable")
        self.assertEqual(report["source_status"]["17lands"]["status"],"unavailable")
        self.assertEqual(report["source_status"]["17lands"]["error_type"],"ValueError")

    def test_discovery_degrades_when_17lands_network_fails(self):
        from tempfile import TemporaryDirectory
        from unittest.mock import patch
        import json
        scryfall={"data":[{"code":"TRK","name":"Star Trek","set_type":"expansion",
            "released_at":"2026-11-20","digital":False,"card_count":311}]}
        def fake_fetch(url, timeout=90):
            if url==set_catalog.SETS_API: return json.dumps(scryfall).encode()
            if url==set_catalog.LANDS: raise TimeoutError("listing timed out")
            raise AssertionError(url)
        with TemporaryDirectory() as directory:
            root=Path(directory)
            (root/"scripts/data").mkdir(parents=True)
            (root/"scripts/data/reviewed_archetypes.json").write_text('{"sets":{}}')
            (root/"scripts/data/reviewed_cards.json").write_text('{"sets":{}}')
            with patch.object(set_catalog,"fetch",side_effect=fake_fetch):
                report=set_catalog.discover(root)
        self.assertEqual(report["sets"][0]["17lands_status"],"unavailable")
        self.assertEqual(report["source_status"]["17lands"]["error_type"],"TimeoutError")


    def test_candidate_archive_url_uses_public_filename_convention(self):
        self.assertEqual(
            set_catalog.candidate_archive_url("draft", "FRA", "PremierDraft"),
            "https://data.17landscapes.com/analysis_data/draft_data/draft_data_public.FRA.PremierDraft.csv.gz",
        )
        self.assertEqual(
            set_catalog.candidate_archive_url("game", "ECL", "PremierDraft"),
            "https://data.17landscapes.com/analysis_data/game_data/game_data_public.ECL.PremierDraft.csv.gz",
        )

    def test_candidate_archive_url_rejects_unknown_archive_kind(self):
        with self.assertRaises(ValueError):
            set_catalog.candidate_archive_url("other", "FRA", "PremierDraft")

    def test_candidate_probe_requires_gzip_response(self):
        response=MagicMock()
        response.status=206
        response.__enter__.return_value=response
        response.read.return_value=bytes((31, 139))
        with patch.object(set_catalog,"urlopen",return_value=response):
            result=set_catalog.probe_candidate_url("https://data.17landscapes.com/example.csv.gz")
        self.assertEqual(result["status"],"available")

    def test_candidate_probe_reports_missing_url(self):
        from urllib.error import HTTPError
        with patch.object(set_catalog,"urlopen",side_effect=HTTPError("https://example.test",404,"Not Found",{},None)):
            result=set_catalog.probe_candidate_url("https://data.17landscapes.com/example.csv.gz")
        self.assertEqual(result,{"status":"url_not_available","http_status":404})

    def test_acquire_falls_back_to_convention_urls_when_catalog_unavailable(self):
        from tempfile import TemporaryDirectory
        import json
        cards={"data":[{"set_name":"Foundations Example","name":"Test Card"}]}
        def fake_fetch(url,timeout=90):
            if url.startswith(set_catalog.CARDS_API): return json.dumps(cards).encode()
            if url==set_catalog.LANDS: return b"<html><head></head></html>"
            raise AssertionError(url)
        downloaded=[]
        def fake_download(url,path):
            downloaded.append(url)
            return {"url":url,"path":str(path),"bytes":12,"sha256":"abc","physical_lines":3,"gzip_valid":True}
        with TemporaryDirectory() as directory:
            with (
                patch.object(set_catalog,"fetch",side_effect=fake_fetch),
                patch.object(set_catalog,"download_archive",side_effect=fake_download),
                patch.object(set_catalog,"discover_guide",return_value=(None,"not_found")),
            ):
                result=set_catalog.acquire("FRA","PremierDraft","",Path(directory))
        self.assertEqual(set(downloaded),{
            "https://data.17landscapes.com/analysis_data/draft_data/draft_data_public.FRA.PremierDraft.csv.gz",
            "https://data.17landscapes.com/analysis_data/game_data/game_data_public.FRA.PremierDraft.csv.gz",
        })
        self.assertEqual(result["17lands"]["probes"]["draft"],"acquired")
        self.assertEqual(result["17lands"]["probes"]["game"],"acquired")
        self.assertEqual(result["status"]["17lands"],"acquired")

if __name__=="__main__": unittest.main()
