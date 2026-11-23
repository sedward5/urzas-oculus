import sys, unittest
from unittest.mock import patch, MagicMock
from urllib.error import HTTPError
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import set_catalog

class CatalogTests(unittest.TestCase):
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
    def test_archive_url_uses_expected_public_key(self):
        self.assertEqual(
            set_catalog.archive_url("TRK","PremierDraft","draft"),
            "https://17lands-public.s3.amazonaws.com/analysis_data/draft_data/draft_data_public.TRK.PremierDraft.csv.gz"
        )

    def test_probe_archive_success_and_not_found(self):
        response=MagicMock()
        response.status=200
        response.__enter__.return_value=response
        with patch.object(set_catalog,"urlopen",return_value=response):
            self.assertTrue(set_catalog.probe_archive("https://example.test/archive"))
        with patch.object(set_catalog,"urlopen",side_effect=HTTPError("u",404,"Not Found",{},None)):
            self.assertFalse(set_catalog.probe_archive("https://example.test/missing"))

    def test_probe_archive_does_not_hide_access_denied(self):
        with patch.object(set_catalog,"urlopen",side_effect=HTTPError("u",403,"Forbidden",{},None)):
            self.assertIsNone(set_catalog.probe_archive("https://example.test/private"))

    def test_guide_domain_guard_runs_before_network(self):
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as d:
            with self.assertRaises(ValueError): set_catalog.acquire("TRK","PremierDraft","https://example.com/x",Path(d))
if __name__=="__main__": unittest.main()
