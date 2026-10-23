"""Independent movement-policy corruption tests using a retained physical witness."""
import json,tempfile,unittest
from pathlib import Path
from audit_mixed_avr_500 import audit
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'artifacts/p2_mixed_avr_reserve_20261023/scan-security-master-guard-shard-3-of-3/generator_60'
class P2MovementAuditTests(unittest.TestCase):
    def replay(self,kind=None,preventive=False):
        with tempfile.TemporaryDirectory() as td:
            folder=Path(td)
            for name in ['contract.json','result.json',*[f'period-{t}.json' for t in range(1,6)]]:
                data=json.loads((SOURCE/name).read_text())
                if kind and name.startswith('period-'):
                    study=data['data'];policy=study['control_policy']
                    policy[kind]='preventive' if preventive else 'corrective'
                    key='tap_movement_limits' if kind=='taps' else 'shunt_movement_limits'
                    controls='tap_controls' if kind=='taps' else 'shunt_controls'
                    ident='branch_id' if kind=='taps' else 'bank_id'
                    policy[key]=None if preventive else {str(c[ident]):0. for c in study[controls]}
                (folder/name).write_text(json.dumps(data))
            return audit(folder)
    def test_original_witness(self):self.assertTrue(self.replay()['valid'])
    def test_zero_tap_movement_rejected(self):self.assertFalse(self.replay('taps')['valid'])
    def test_zero_bank_movement_rejected(self):self.assertFalse(self.replay('shunts')['valid'])
    def test_preventive_taps_rejected(self):self.assertFalse(self.replay('taps',True)['valid'])
    def test_preventive_banks_rejected(self):self.assertFalse(self.replay('shunts',True)['valid'])
if __name__=='__main__':unittest.main()
