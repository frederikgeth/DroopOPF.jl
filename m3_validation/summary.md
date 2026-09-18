# M3 droop-design validation

- Training valid: `true`
- Held-out line-33 valid: `true`
- Reference objective: 1.676309943232809e-5
- Optimized objective: 1.6501095692742863e-5
- Objective improvement: 2.6200373958522555e-7
- G9 slope: 0.06374097069130857
- G9 voltage reference: 1.0006135926480557
- G9 lower deadband width: 0.009386407591181376
- G9 upper deadband width: 0.009999999999999908

The optimized settings are shared across the base case and all training
contingencies. Both training and held-out states are independently replayed
against the reconstructed exact piecewise-linear droop curve.
