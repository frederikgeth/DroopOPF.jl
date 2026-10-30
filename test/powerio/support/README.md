# Corrected-library test fixture

`powerio-0.11.7-qualification.patch` contains the minimal Rust corrections for
[PowerIO #772](https://github.com/eigenergy/powerio/issues/772) and
[#773](https://github.com/eigenergy/powerio/issues/773). It applies to PowerIO
v0.11.7, commit `d104aa5b47fa436b0eb8cf833c2c32ab43b2f704`.
The source is available under MIT OR Apache-2.0; the MIT license is retained in
`LICENSE.PowerIO`.

This fixture is used only to build the CI validation library. DroopOPF never
installs this patch, changes PowerIO preferences, or substitutes a library at
runtime. The separate released-library CI job uses the published artifact and
requires its known rejection paths. The corrected job requires successful
transformer imports and frequency-preserving RAW exports, so these success
paths cannot disappear behind capability-dependent test branches.

To reproduce, check out the exact upstream commit in a separate directory,
apply this patch with `git apply`, and run `cargo build --locked -p powerio-capi`.
Set `POWERIO_CAPI` to the resulting shared library and
`DROOPOPF_POWERIO_TEST_PROFILE=corrected` before running this integration suite.
The library suffix is `.so` on Linux and `.dylib` on macOS.

Replace this fixture and update the capability expectations when a published
PowerIO release containing both fixes is qualified. It is not a production
dependency or a replacement for an upstream release.
