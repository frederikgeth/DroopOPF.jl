Subject: CCOpt 0.1.0 exact-PWL complementarity accuracy / termination question

Hello CCOpt maintainers,

I am evaluating CCOpt 0.1.0 on an AC OPF model with continuous transformer
taps, continuous shunt-bank susceptance, and voltage--reactive-power droop
controllers represented with exact PWL complementarity. I have prepared a
self-contained frozen reproduction report here:

`artifacts/s1_ccopt_frozen/DEVELOPER_REPORT.md`

The corresponding runner is:

`examples/s1_ccopt_policy_matrix.jl`

The 12-cell matrix uses IEEE 118/300, nominal/+5% load, and three declared
starts. Each cell uses a 1000-inner-iteration / 60-second native profile and
has an independent direct physical droop audit at `1e-5` pu. Two IEEE 118 cells
validate. The remaining ten end at an iteration or time limit and are rejected
with large direct residuals; I do not interpret those as accepted solutions.

The point I would value guidance on is a converged IEEE 118 diagnostic: CCOpt
reported complementarity and relaxed-NLP primal/dual metrics around `9e-13`,
while the directly evaluated physical PWL droop residual was `1.663e-5` pu.
The retained encoding audit locates a small hinge discrepancy that is amplified
by the droop slope, rather than a variable extraction/projection mismatch.
Tightening the relaxation/tolerances improves that one residual, but not the
full placement matrix consistently.

Could you advise on the recommended termination/relaxation or post-solve polish
strategy for accurate PWL complementarity primal recovery? I would also welcome
advice on whether MOI can expose an outer-homotopy count and a portable
warm-start/reset mechanism for this use case.

Thank you,
[Name]
