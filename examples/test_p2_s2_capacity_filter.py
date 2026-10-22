"""Adversarial checks of the S2-specific necessary capacity condition."""
import copy,unittest
from p2_s2_capacity_filter import capacity_certificate
class CapacityTests(unittest.TestCase):
 def setUp(self):
  self.study={'case':{'base_power':100.,'generators':[dict(id=i,available=True,p_min=0.,p_max=1.) for i in (1,2,3)],'attachments':[],'controls':[],
   'loads':[{'p':2.5}], 'network':{'buses':[{}], 'branches':[{'available':True,'resistance':.1}],'shunts':[],'banks':[]}},
   'participation':{'1':1.,'2':1.,'3':1.},'redispatch_limits':{}}
  self.base={'state':{'pg':[1.,.75,.75]}};self.event={'generator_ids':[3]}
 def screen(self,**kw):return capacity_certificate(self.study,self.base,self.event,active_response='s2_proportional_v1',**kw)
 def test_saturated_survivor_blocks_proportional_response(self):self.assertTrue(self.screen()['certified_infeasible'])
 def test_no_false_exclusion_with_ample_capacity(self):
  self.study['case']['loads'][0]['p']=1.;self.assertFalse(self.screen()['certified_infeasible'])
 def test_response_policy_must_be_explicit(self):
  self.assertFalse(capacity_certificate(self.study,self.base,self.event)['certified_infeasible'])
  self.assertFalse(capacity_certificate(self.study,self.base,self.event,active_response='limit_aware')['certified_infeasible'])
 def test_nonpassive_branch_falls_back(self):
  self.study['case']['network']['branches'][0]['resistance']=-.1;self.assertFalse(self.screen()['certified_infeasible'])
 def test_nonpassive_shunt_falls_back(self):
  self.study['case']['network']['shunts']=[{'available':True,'conductance':-.1}];self.assertFalse(self.screen()['certified_infeasible'])
 def test_nonpassive_bank_falls_back(self):
  self.study['case']['network']['banks']=[{'available':True,'step_conductances':[-.1]}];self.assertFalse(self.screen()['certified_infeasible'])
 def test_equality_is_inconclusive_and_tolerance_is_conservative(self):
  # Small deficits inside the physical validator's tolerance cannot be certified.
  self.study['case']['loads'][0]['p']=(1.75+.1)/.99
  self.assertFalse(self.screen()['certified_infeasible'])
 def test_no_participant_falls_back(self):
  self.study['participation']={};self.assertFalse(self.screen()['certified_infeasible'])
 def test_redispatch_limit_can_tighten_certificate(self):
  self.base['state']['pg']=[.8,.8,.8];self.study['redispatch_limits']={'1':0.,'2':0.};self.assertTrue(self.screen()['certified_infeasible'])
 def test_nonfinite_base_falls_back(self):
  self.base['state']['pg'][0]=float('nan');self.assertFalse(self.screen()['certified_infeasible'])
 def test_nonfinite_weight_falls_back(self):
  self.study['participation']['1']=float('inf');self.assertFalse(self.screen()['certified_infeasible'])
 def test_explicit_reactive_policy_falls_back(self):
  self.study['reactive_assignments']=[{}];self.assertFalse(self.screen()['certified_infeasible'])
 def test_invalid_tolerance_falls_back(self):
  self.assertFalse(self.screen(tolerance=-1e-6)['certified_infeasible'])
 def test_nonfinite_resistance_falls_back(self):
  self.study['case']['network']['branches'][0]['resistance']=float('nan');self.assertFalse(self.screen()['certified_infeasible'])
 def test_nonfinite_tolerance_falls_back(self):
  self.assertFalse(self.screen(tolerance=float('inf'))['certified_infeasible'])
 def test_corrective_dispatch_policy_falls_back(self):
  self.study['mode']='corrective';self.assertFalse(self.screen()['certified_infeasible'])
if __name__=='__main__':unittest.main()
