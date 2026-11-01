"""Publication-boundary regressions using minimal rendered-site fixtures."""
import contextlib,io,tempfile,unittest
from pathlib import Path
from check_teaching_docs import check
class PublicDocsTests(unittest.TestCase):
 def run_site(self,files):
  with tempfile.TemporaryDirectory() as tmp:
   for name,text in files.items():
    p=Path(tmp)/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
   with contextlib.redirect_stdout(io.StringIO()):return check(tmp)
 def test_public_teaching_page_and_defined_power_symbol(self):
  self.assertTrue(self.run_site({'index.html':'<h1 id="start">AC model</h1><p>S is complex power.</p><a href="#start">Start</a>'})['valid'])
 def test_internal_labels_are_rejected(self):
  for text in ['M1','M9.2','S2','P3','Milestone','Architecture','Roadmap','Agenda','Research']:
   with self.subTest(text=text):self.assertFalse(self.run_site({'index.html':'<p>'+text+'</p>'})['valid'])
 def test_hidden_direct_url_is_rejected_without_navigation_link(self):
  for name in ['research.html','milestones/index.html','ARCHITECTURE.md','agenda/index.html']:
   with self.subTest(name=name):self.assertFalse(self.run_site({'index.html':'<p>Guide</p>',name:'<p>Local record</p>'})['valid'])
 def test_search_index_cannot_leak_excluded_content(self):
  self.assertFalse(self.run_site({'index.html':'<p>Guide</p>','search_index.js':'[{"title":"M3"}]'})['valid'])
 def test_unlinked_evidence_assets_are_not_public(self):
  self.assertFalse(self.run_site({'index.html':'<p>Guide</p>','assets/validation/catalog.json':'{}'})['valid'])
 def test_links_and_image_accessibility_still_checked(self):
  self.assertFalse(self.run_site({'index.html':'<a href="missing.html">Guide</a><img src="assets/teaching/missing.svg">'})['valid'])
 def test_empty_output_is_not_a_success(self):self.assertFalse(self.run_site({})['valid'])
if __name__=='__main__':unittest.main()
