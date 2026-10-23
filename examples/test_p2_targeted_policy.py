"""Reject hidden physical/control relaxation in a claimed unchanged-policy recovery."""
import copy,json,unittest
from pathlib import Path
from report_p2_targeted import policy_identity
ROOT=Path(__file__).resolve().parents[1]
class PolicyIdentityTests(unittest.TestCase):
    def setUp(self):
        old=ROOT/'artifacts/p2_mixed_limit_aware_20261023/p2-base';new=ROOT/'artifacts/p2_targeted_relaxations_20261023/joint-five'
        self.a=[json.loads((old/f'period-{i}.json').read_text())['data'] for i in range(1,6)]
        self.b=[json.loads((new/f'period-{i}.json').read_text())['data'] for i in range(1,6)]
        self.x=json.loads((old/'contract.json').read_text());self.y=json.loads((new/'contract.json').read_text())
    def valid(self):return policy_identity(self.a,self.b,self.x,self.y)
    def test_native_unchanged_policy(self):self.assertTrue(self.valid())
    def test_thermal_uprating(self):
        self.b[0]['case']['network']['branches'][0]['thermal_limit']*=1.1;self.assertFalse(self.valid())
    def test_voltage_extension(self):
        self.b[0]['case']['network']['buses'][0]['v_max']+=.01;self.assertFalse(self.valid())
    def test_generator_uprating(self):
        g=next(g for g in self.b[0]['case']['generators'] if g.get('s_rated'));g['s_rated']*=1.05;self.assertFalse(self.valid())
    def test_tap_budget(self):
        p=self.b[0]['control_policy']['tap_movement_limits'];p[next(iter(p))]*=2;self.assertFalse(self.valid())
    def test_avr_bounds(self):
        p=self.y['avr_bounds'];p[next(iter(p))][1]+=.01;self.assertFalse(self.valid())
    def test_droop_bounds(self):
        self.y['droop_controls'][0]['bounds']['slope'][1]*=2;self.assertFalse(self.valid())
    def test_response_change(self):
        self.y['response']='s2_proportional';self.assertFalse(self.valid())
    def test_load_relief_change(self):
        self.y['s2_emergency']=True;self.assertFalse(self.valid())
    def test_missing_period(self):
        self.b.pop();self.assertFalse(self.valid())
if __name__=='__main__':unittest.main()
