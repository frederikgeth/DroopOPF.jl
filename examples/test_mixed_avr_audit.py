"""Corruption checks against a real accepted nominal mixed-control witness."""
import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from audit_mixed_avr_500 import audit
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'artifacts/p2_mixed_avr_500_20261022/nominal-fixed-r6'

class ReplayTests(unittest.TestCase):
    def run_corruption(self,change=None):
        with tempfile.TemporaryDirectory(prefix='mixed-audit-') as d:
            target=Path(d)
            for name in ('contract.json','period-1.json','result.json'):
                shutil.copyfile(SOURCE/name,target/name)
            if change:change(target)
            return audit(target)['valid']
    def mutate(self,path,f):
        data=json.loads(path.read_text());f(data);path.write_text(json.dumps(data))
    def test_original(self):self.assertTrue(self.run_corruption())
    def test_generator_power(self):
        self.assertFalse(self.run_corruption(lambda p:self.mutate(p/'result.json',lambda d:d['data']['periods'][0]['states']['base']['pg'].__setitem__(0,9.))))
    def test_apparent_rating(self):
        self.assertFalse(self.run_corruption(lambda p:self.mutate(p/'period-1.json',lambda d:next(g for g in d['data']['case']['generators'] if g['available']).__setitem__('s_rated',1e-6))))
    def test_avr_target(self):
        self.assertFalse(self.run_corruption(lambda p:self.mutate(p/'result.json',lambda d:next(a for a in d['data']['periods'][0]['reactive_assignments'] if a['mode']['type']=='AVR')['mode'].__setitem__('voltage_setpoint',1.2))))
    def test_thermal_rating(self):
        self.assertFalse(self.run_corruption(lambda p:self.mutate(p/'period-1.json',lambda d:d['data']['case']['network']['branches'][0].__setitem__('thermal_limit',1e-9))))
    def test_objective(self):
        self.assertFalse(self.run_corruption(lambda p:self.mutate(p/'result.json',lambda d:d['data'].__setitem__('objective_mwh',0.))))
    def test_response_contract(self):
        self.assertFalse(self.run_corruption(lambda p:self.mutate(p/'contract.json',lambda d:d.__setitem__('response','limit_aware'))))
    def test_time_contract(self):
        self.assertFalse(self.run_corruption(lambda p:self.mutate(p/'contract.json',lambda d:d.__setitem__('duration_hours',[2.]))))

    def test_priority_metadata(self):
        self.assertFalse(self.run_corruption(lambda p:self.mutate(p/'result.json',lambda d:d['data']['stages'][0].__setitem__('name','feasibility'))))
    def test_frozen_base_reference(self):
        source=ROOT/'artifacts/p2_mixed_avr_500_20261022/scan-fixed/branch_4'
        with tempfile.TemporaryDirectory(prefix='mixed-freeze-') as d:
            target=Path(d)
            for name in ('contract.json','result.json',*[f'period-{t}.json' for t in range(1,6)]):
                shutil.copyfile(source/name,target/name)
            self.assertTrue(audit(target)['valid'])
            self.mutate(target/'contract.json',lambda spec:spec['fixed_base_reference'][0]['state']['pg'].__setitem__(0,99.))
            self.assertFalse(audit(target)['valid'])
    def test_capacity_filter_refuses_limit_aware(self):
        from mixed_avr_capacity_screen import screen
        with tempfile.TemporaryDirectory(prefix='mixed-response-') as d:
            p=Path(d);(p/'candidate').mkdir();(p/'candidate/result.json').write_text(json.dumps({'data':{'response':'limit_aware'}}))
            with self.assertRaises(ValueError):screen(p,'candidate')
    def test_outer_projection_preserves_response_support(self):
        from mixed_avr_capacity_screen import active_only_projection
        source={'case':{'generators':[{'id':1,'available':True,'p_min':0.,'p_max':1.,'s_rated':.3}],
            'controls':[],'attachments':[],'network':{'banks':[]}},'participation':{'1':1.},'shunt_controls':[],
            'reactive_assignments':[{'generator_id':1,'mode':{'type':'VoltVarDroop','capability':{'p_min':.3,'p_max':.3}}}]}
        outer=active_only_projection(source)
        self.assertEqual(outer['participation']['1'],0.)
        self.assertIsNone(outer['case']['generators'][0]['s_rated'])
        self.assertEqual(source['participation']['1'],1.)
        self.assertEqual(source['case']['generators'][0]['s_rated'],.3)

if __name__=='__main__':unittest.main()
