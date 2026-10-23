"""Fault-injection tests against a newly native/physically accepted point."""
import copy,json,shutil,tempfile,unittest
from pathlib import Path
from audit_p2_open_gates import ROOT,OUT,load,check_attempt,resource_totals
SOURCE=OUT/'cold-hybrid-catalogue/batch-1/primary'
class EvidenceCorruption(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.p=Path(self.tmp.name)/'attempt';shutil.copytree(SOURCE,self.p)
 def tearDown(self):self.tmp.cleanup()
 def edit(self,name,change):
  p=self.p/name;d=load(p);change(d);p.write_text(json.dumps(d))
 def test_original_passes(self):self.assertTrue(check_attempt(self.p)['accepted'])
 def test_frozen_base_change_rejected(self):
  self.edit('point-solve.json',lambda d:next(r for r in d['states'] if r['id']=='base')['state']['pg'].__setitem__(0,.02))
  with self.assertRaises(AssertionError):check_attempt(self.p)
 def test_missing_outage_rejected(self):
  self.edit('point-solve.json',lambda d:d['states'].pop())
  with self.assertRaises(AssertionError):check_attempt(self.p)
 def test_changed_common_curve_rejected(self):
  self.edit('controller-solve.json',lambda d:d['data']['case']['controls'][0].__setitem__('slope',d['data']['case']['controls'][0]['slope']*1.01))
  with self.assertRaises(AssertionError):check_attempt(self.p)
 def test_consistent_but_false_native_flag_rejected(self):
  self.edit('point-solve.json',lambda d:d['record'].__setitem__('native_success',False))
  self.edit('summary.json',lambda d:d['record'].__setitem__('native_success',False))
  self.edit('stages.json',lambda d:d[-1].__setitem__('native_success',False))
  with self.assertRaises(AssertionError):check_attempt(self.p)
 def test_false_resource_cap_rejected(self):
  totals=resource_totals(load(self.p/'controller-solve.json')['data'],load(self.p/'point-solve.json'))
  kind=next(k for k in ('shedding','dr') if totals[k]>1e-5)
  self.edit('contract.json',lambda d:d.__setitem__('resource_caps',{kind:0.}))
  with self.assertRaises(AssertionError):check_attempt(self.p)
if __name__=='__main__':unittest.main()
