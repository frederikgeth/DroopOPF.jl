"""Contract corruption checks for reserve-aware dispatch evidence."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from audit_mixed_avr_500 import audit

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'artifacts/p2_mixed_avr_reserve_20261023/reserve-base'

class ReserveAuditTests(unittest.TestCase):
    def replay(self,mutate=None):
        with tempfile.TemporaryDirectory() as td:
            folder=Path(td)
            payload={p.name:json.loads(p.read_text()) for p in SOURCE.glob('*.json')
                     if p.name in {'contract.json','result.json'} or p.name.startswith('period-')}
            if mutate:mutate(payload)
            for name,data in payload.items():(folder/name).write_text(json.dumps(data))
            return audit(folder)['valid']

    def test_native_base(self):self.assertTrue(self.replay())
    def test_missing_reserve_stage(self):
        self.assertFalse(self.replay(lambda d:d['result.json']['data']['stages'].pop(0)))
    def test_false_reserve_floor(self):
        self.assertFalse(self.replay(lambda d:d['result.json']['data']['stages'][0].update(objective=-.9)))
    def test_changed_objective_contract(self):
        self.assertFalse(self.replay(lambda d:d['contract.json'].update(objective_policy='loss')))
    def test_unprovided_replacement_reserve(self):
        self.assertFalse(self.replay(lambda d:d['contract.json'].update(reserve_generator_outages=[60])))
    def test_avr_movement_violation(self):
        def change(d):
            r=d['result.json']['data'];key=next(iter(r['avr_targets'][1]));r['avr_targets'][1][key]+=.02
        self.assertFalse(self.replay(change))
    def test_avr_bounds_violation(self):
        def change(d):
            r=d['result.json']['data'];key=next(iter(r['avr_targets'][0]));r['avr_targets'][0][key]=2.
        self.assertFalse(self.replay(change))

if __name__=='__main__':unittest.main()
