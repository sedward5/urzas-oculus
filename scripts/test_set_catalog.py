import sys, unittest
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
    def test_empty_listing_fails_closed(self):
        with self.assertRaises(ValueError): set_catalog.parse_lands("<html>maintenance</html>")
    def test_guide_domain_guard(self):
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as d:
            with self.assertRaises(ValueError): set_catalog.acquire("TRK","PremierDraft","https://example.com/x",Path(d))
if __name__=="__main__": unittest.main()
