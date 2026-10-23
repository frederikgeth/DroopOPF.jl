"""Load and verify the authoritative S2 data/configuration for P2; never optimize.

Legacy S2 coupled states retain their original proportional response semantics.
A current Study deserialization must not silently reinterpret those states.
"""
from pathlib import Path
import copy
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'artifacts/p2_s2_500'


def load_inputs(package=PACKAGE):
    contract = json.loads((package / 'contract.json').read_text())
    inputs = {}
    for role, ref in contract['inputs'].items():
        snapshot = package / ref['snapshot']
        source = ROOT / ref['source']
        if snapshot.read_bytes() != source.read_bytes():
            raise ValueError(f'S2 data changed: {role}')
        if hashlib.sha256(snapshot.read_bytes()).hexdigest() != ref['sha256']:
            raise ValueError(f'S2 hash mismatch: {role}')
        inputs[role] = json.loads(snapshot.read_text())
    for rel, expected in contract['source_hashes'].items():
        if hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() != expected:
            raise ValueError(f'S2/library source drift: {rel}')
        if hashlib.sha256((package / 'source_snapshot' / rel).read_bytes()).hexdigest() != expected:
            raise ValueError(f'S2/library snapshot drift: {rel}')
    validate_contract(contract, inputs)
    return contract, inputs


def validate_contract(contract, inputs):
    study = inputs['shared_controller']['data']
    protocol = inputs['campaign_protocol']
    for key in ('control_policy', 'participation', 'redispatch_limits'):
        if contract[key] != study[key]:
            raise ValueError(f'S2 policy mismatch: {key}')
    for key, source in (('tap_controls', 'taps'), ('shunt_controls', 'shunts')):
        if contract[key] != protocol[source]:
            raise ValueError(f'S2 selected equipment mismatch: {key}')
    physical_keys = ('dr_fraction_per_positive_load', 'shedding_mw_per_contingency',
                     'combined_fraction_per_load', 'proportional_q_relief',
                     'basecase_emergency_or_relief', 'voltage_extension_pu',
                     'confirmed_thermal_multiplier', 'priorities')
    if contract['physical_policy'] != {k: inputs['emergency_protocol'][k] for k in physical_keys}:
        raise ValueError('S2 emergency/relief mismatch')
    if contract['scopes']['shared_checkpoint_demands'] != inputs['shared_contract']['factors']:
        raise ValueError('S2 shared demand scope mismatch')
    if contract['scopes']['expansion_ceiling'] != protocol['maximum_demand']:
        raise ValueError('S2 expansion ceiling mismatch')
    if contract['active_response']['law'] != 'Pg_s = Pg_base + alpha_s * delta_s':
        raise ValueError('S2 active response law mismatch')
    case = study['case']
    assert len(case['network']['buses']) == 500
    assert len(case['generators']) == 90 and len(case['controls']) == 51
    assert len(contract['tap_controls']) == 131 and len(contract['shunt_controls']) == 11
    assert all(study['participation'].get(str(g['id']), 0) == g['p_max']
               for g in case['generators'] if g['available'])
    calibrated = inputs['calibrated_case']['data']['case']['controls']
    expected = [dict(control_id=i+1,
                     slope_bounds=[.02/(d['capability']['q_max']-d['capability']['q_min']),
                                   .08/(d['capability']['q_max']-d['capability']['q_min'])],
                     v_ref_bounds=[d['schedule']['v_ref']-.02, d['schedule']['v_ref']+.02])
                for i, d in enumerate(calibrated)]
    if contract['droop_design_controls'] != expected:
        raise ValueError('S2 droop bounds mismatch')
    assert inputs['shared_audit']['accepted']
    assert inputs['independent_105_audit']['accepted']
    assert inputs['checkpoint']['status'] == 'paused_by_user'


def preflight():
    contract, inputs = load_inputs()
    negative = []
    for field, value in [('control_policy', {}), ('tap_controls', []),
                         ('participation', {}), ('droop_design_controls', []),
                         ('physical_policy', {}), ('active_response', {'law': 'changed'})]:
        bad = copy.deepcopy(contract)
        bad[field] = value
        try:
            validate_contract(bad, inputs)
        except ValueError:
            negative.append(field)
        else:
            raise AssertionError(f'Failed to reject changed {field}')
    output = dict(passed=True, byte_identical_inputs=len(inputs),
                  taps=len(contract['tap_controls']), banks=len(contract['shunt_controls']),
                  shared_droop_parameters=102, rejected_policy_corruptions=negative,
                  optimizer_calls=0, benchmark_status=contract['status'],
                  s2_campaign_resumed=False)
    print(json.dumps(output, indent=2))
    return output


if __name__ == '__main__':
    preflight()
