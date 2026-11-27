from pathlib import Path
import tempfile,unittest
from check_boundaries import check
class BoundaryTests(unittest.TestCase):
 def tree(self,d):
  p=Path(d);(p/'src').mkdir();(p/'Project.toml').write_text('name="DroopOPF"\nuuid="e6b4e7b0-8d6a-4d22-9b7c-3c4d6c4e4d2a"\n');return p
 def test_static_tree(self):
  with tempfile.TemporaryDirectory() as d:self.assertEqual(check(self.tree(d)),[])
 def test_research_dependency(self):
  with tempfile.TemporaryDirectory() as d:
   p=self.tree(d);(p/'Project.toml').write_text((p/'Project.toml').read_text()+'[deps]\nDroopDesign="x"\n');self.assertTrue(check(p))
 def test_dynamic_import(self):
  with tempfile.TemporaryDirectory() as d:
   p=self.tree(d);(p/'src/dynamics.jl').write_text('using PowerDynamics\n');self.assertTrue(check(p))
 def test_research_tree(self):
  with tempfile.TemporaryDirectory() as d:
   p=self.tree(d);(p/'tools/q').mkdir(parents=True);self.assertTrue(check(p))
if __name__=='__main__':unittest.main()
