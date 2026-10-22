"""Summarize the twelve saved zero-deadband S1 replays; performs no solves."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/s1_zero_deadband/expanded'
data = json.loads((OUT / 'summary.json').read_text())
rows = data['attempts']
assert len(rows) == 12 and len({r['name'] for r in rows}) == 12
assert all(not r['original_accepted'] for r in rows)
for path, expected in data['code_hashes'].items():
    assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected, path
for r in rows:
    for path_key, hash_key in [('source_attempt', 'source_sha256'), ('seed_path', 'seed_sha256')]:
        assert hashlib.sha256((ROOT / r[path_key]).read_bytes()).hexdigest() == r[hash_key]
    assert r['accepted'] == (r['solver_success'] and r['point_pass'])

prior = [json.loads(p.read_text()) for p in (ROOT / 'artifacts/s1_arpae500/attempts').glob('*.json')]
comparisons = []
for r in rows:
    old = json.loads((ROOT / r['source_attempt']).read_text())
    if r['kind'] == 'original-start':
        candidates = [p for p in prior if p['accepted'] and p.get('objective_kind') == 'loss'
                      and p.get('contract', {}).get('model') == r['model_fingerprint']
                      and not p.get('operating_bounds')]
        ref = min(candidates, key=lambda p: p['loss_mw']) if candidates else None
    else:
        path = (ROOT / r['source_attempt']).with_name('retry-' + old['name'] + '.json')
        ref = json.loads(path.read_text()) if path.exists() else None
        if ref and not ref['accepted']:
            ref = None
    comparisons.append(dict(name=r['name'], reference_name=ref['name'] if ref else None,
                            reference_loss_mw=ref['loss_mw'] if ref else None,
                            delta_loss_mw=r['loss_mw']-ref['loss_mw'] if ref and r['point_pass'] else None))
(OUT / 'comparisons.json').write_text(json.dumps(comparisons, indent=2) + '\n')

def fmt(value, digits=3):
    return '—' if value is None else f'{value:.{digits}f}'

lines = ['# Expanded S1 zero-deadband replay', '',
         f"**Accepted: {sum(r['accepted'] for r in rows)}/12; physical checks passed: {sum(r['point_pass'] for r in rows)}/12.**", '',
         'Six original 90%/95% failed CCOpt starts and six failed closeout-profile primaries were replayed serially. Saved case and initial-state hashes, equipment and droop policies, angle limits, loss objective, solver settings, and 1,000-iteration/60-second budgets were preserved. No retries were added. All runs are S1 base-case optimizations.', '',
         '| Attempt | Original status | New status | Physical | Loss MW | Iterations old → new | Solve wall s old → new |',
         '|---|---|---|---|---:|---:|---:|']
for r in rows:
    d = r.get('ccopt_diagnostics', {})
    lines.append(f"| {r['name']} | {r['original_status']} | {r.get('solver_status', r.get('error'))} | {'Pass' if r['point_pass'] else 'Fail'} | {fmt(r.get('loss_mw'), 6)} | {r['original_iterations'] if r['original_iterations'] is not None else '—'} → {d.get('inner_iterations', '—')} | {fmt(r['original_solve_wall_seconds'])} → {fmt(r.get('solve_wall_seconds'))} |")
lines += ['', 'Old losses at rejected iterates are not treated as feasible objective benchmarks. The table below compares new independently accepted losses with accepted historical references. For the six original starts, the reference is the best saved loss result with the same model fingerprint and no extra original-limit overlay. For profile cells, it is the accepted bounded retry of that same cell.', '',
          '| Attempt | Accepted historical reference | Reference loss MW | New minus reference MW |',
          '|---|---|---:|---:|']
for c in comparisons:
    lines.append(f"| {c['name']} | {c['reference_name'] or '—'} | {fmt(c['reference_loss_mw'], 6)} | {fmt(c['delta_loss_mw'], 6)} |")
failed = [r for r in rows if not r['accepted']]
if failed:
    lines += ['', '## Remaining failures', '']
    for r in failed:
        physical = r.get('point_checks', {}).get('physical', {})
        lines.append(f"`{r['name']}` terminates as `{r.get('solver_status')}`. Independent power-balance residual is {physical.get('power_balance_max', float('nan')):.6g} pu; violations: {', '.join(physical.get('violations', []))}. Droop residual is {physical.get('droop_residual_max', float('nan')):.6g} pu and the control policy passes: {r.get('design_policy_valid')}. This is a retained failed local solve, not an infeasibility certificate. The historical conditioned retry remains a valid witness; this replay does not replace it.")
        lines.append('')
audits = [r['ccopt_encoding_audit'] for r in rows if 'ccopt_encoding_audit' in r]
max_raw = max(a['max_raw_droop_error_pu'] for a in audits)
max_exact = max(a['max_exact_droop_error_pu'] for a in audits)
lines += ['', f'Maximum encoded raw-response error: {max_raw:.3g} pu. Maximum exact-droop error: {max_exact:.3g} pu. Each 500-bus model uses 102 reactive-projection complementarity pairs, removing 102 voltage-hinge pairs and 204 auxiliary variables. Free-droop policy checks remain separate from native solver termination and independent AC/limit validation.', '',
          'These timings describe historical and current attempts, not a controlled speed ranking. The first new build/solve may include compilation; no warmup is scored separately here. Historical profile cells were warmed, known-witness replays. Local objectives may differ between accepted equilibria, and neither accepted termination nor these comparisons establishes global optimality or universal convergence.', '',
          'Original S1 files remain unchanged. Source and seed hashes are checked by this reporter. Full attempt details, returned joint designs, original contracts, model fingerprints, diagnostics, and source-code hashes are retained beside this report.', '',
          '```sh', 'julia --project=. examples/s1_zero_deadband_expanded.jl',
          'python3 examples/report_s1_zero_deadband_expanded.py', '```', '']
(OUT / 'REPORT.md').write_text('\n'.join(lines))
(OUT / 'validation.json').write_text(json.dumps(dict(attempts=12, accepted=sum(r['accepted'] for r in rows),
    physical_passes=sum(r['point_pass'] for r in rows), max_raw_droop_error_pu=max_raw,
    max_exact_droop_error_pu=max_exact, source_and_seed_hashes_verified=True,
    code_hashes_verified=True, scopf_campaign_started=False), indent=2)+'\n')
print('Accepted', sum(r['accepted'] for r in rows), '/12; physical', sum(r['point_pass'] for r in rows), '/12')
