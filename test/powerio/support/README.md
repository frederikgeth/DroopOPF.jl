# PowerIO integration profiles

The released profile pins the Julia wrapper and native artifact to 0.11.7.
Its CZ=2/3 impedance conversion is correct; frequency-preserving construction
remains unsupported. The corrected profile uses official native PowerIO 0.11.9,
commit `e8472dd0d3b80af8642b3232ea41b4e0768f44c1`, with the same Julia wrapper.
Both profiles require transformer-basis qualification. The corrected profile
also requires the frequency-preserving constructor/export behavior.

The earlier local qualification patch used an incorrect nominal-voltage factor
for CZ=2/3. It has been removed. Native 0.11.8 has that incorrect factor;
0.11.9 removes it. Do not restore the old oracle to make a build pass.

CI builds official source with `cargo build --locked -p powerio-capi` and selects
its shared library using process-local `POWERIO_CAPI`. No production install,
persistent preference change or automatic parser fallback occurs. Set
`DROOPOPF_POWERIO_TEST_PROFILE=corrected` for that native build, or `released`
for the stock 0.11.7 artifact. Use the appropriate library for the host platform.
