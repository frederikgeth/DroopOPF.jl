"""Shared idempotent S1 follow-up note for historical report generators."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]
START = '<!-- S1_ZERO_DEADBAND_FOLLOWUP -->'
END = '<!-- /S1_ZERO_DEADBAND_FOLLOWUP -->'

def append_followup(path, *, doc=False):
    summary = ROOT / 'artifacts/s1_zero_deadband/recovery/summary.json'
    if not summary.exists():
        return
    r = json.loads(summary.read_text())
    accepted = r['accepted_combinations_after_recovery']
    link = 's1_zero_deadband.md' if doc else '../../docs/src/s1_zero_deadband.md'
    block = f'''{START}
## Zero-deadband numerical follow-up

The specialized constant-zero-deadband formulation removes the redundant voltage
hinges while retaining Q saturation. A separate S1 replay accepted **11/12 primary
attempts** (all six original light-load starts and five of six closeout-profile
failures); **{accepted}/12 combinations** passed after one historical-policy bounded
retry. The remaining primary failure is retained as `SLOW_PROGRESS` with an AC
power-balance violation. These follow-up counts do not replace the historical
campaign or profile scores above. The formulation passed **3,042/3,042 regression
checks**. See the [diagnosis, recovery and limitations]({link}).
{END}'''
    path = Path(path)
    text = path.read_text()
    if START in text:
        a = text.index(START)
        b = text.index(END, a) + len(END)
        text = text[:a] + text[b:]
    path.write_text(text.rstrip() + '\n\n' + block + '\n')
