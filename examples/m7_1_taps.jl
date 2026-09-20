using DroopOPF, JSON
include("m6_shunt_case.jl")
out=abspath(ARGS[1]); mkpath(out)
c=m6_shunt_case(); start=m5_initial_state(c)
write_study(joinpath(out,"input-study.json"),Study(c))
rows=[]; runs=[]
for tau in range(.95,1.05;length=41)
    swept=with_tap_settings(c,Dict(11=>tau))
    r=solve_opf(swept;smooth_epsilon=1e-5,initial_state=start)
    valid=!isnothing(r.state) && validate_equilibrium(swept,r).valid
    push!(rows,Dict("tap"=>tau,"objective"=>isfinite(r.objective) ? r.objective : nothing,
        "status"=>string(r.termination_status),"valid"=>valid))
end
for (name,controls) in (("fixed",TapControl[]),
    ("tap 11 free",[TapControl(11;lower=.95,upper=1.05,nominal=1.)]),
    ("taps 11 and 22 free",[TapControl(11;lower=.95,upper=1.05,nominal=1.),TapControl(22;lower=.98,upper=1.02)]))
    r=optimize_taps(c,controls;initial_state=start)
    check=validate_tap_design(c,r)
    write_tap_design(joinpath(out,"design-$(length(controls)).json"),r)
    metric=tap_design_metrics(c,r)
    push!(runs,Dict("name"=>name,"valid"=>check.valid,"status"=>string(r.opf.termination_status),
        "objective"=>r.opf.objective,"taps"=>r.taps,"vm"=>r.opf.state.vm,"qg"=>r.opf.state.qg,
        "ac_residual"=>check.physical.power_balance_max,"droop_residual"=>check.physical.droop_residual_max,
        "thermal_margin"=>check.physical.branch_thermal_min_margin,"metrics"=>metric))
end
passed=all(r["valid"] for r in rows) && all(r["valid"] for r in runs) &&
    runs[2]["objective"] <= minimum(r["objective"] for r in rows)+1e-8
write(joinpath(out,"evidence.json"),JSON.json(Dict("pass"=>passed,"sweep"=>rows,"runs"=>runs);pretty=true))
open(joinpath(out,"report.md"),"w") do io
    println(io,"# M7.1 continuous tap optimization\n\nNumerical acceptance: **",passed ? "PASS" : "FAIL","**. Synthetic three-bus base-case OPF, 100 MVA base. Droop settings, phase shifts and shunts are fixed. Branch 22 is explicitly treated as a second adjustable transformer in the two-device experiment.\n")
    println(io,"The objective is the existing sum of squared active dispatch deviations plus 0.001 times squared reactive deviations from generator initial values. Tap deviation and losses are reported separately and do not enter this objective. Ratios are continuous relaxed settings, not discrete positions or switching counts. Local solutions do not certify global optimality.\n")
    println(io,"| Configuration | Objective | AC residual (pu) | Exact droop residual (pu) | Minimum thermal margin | Valid |\n|---|---:|---:|---:|---:|---|")
    for r in runs
        println(io,"| ",r["name"]," | ",r["objective"]," | ",r["ac_residual"]," | ",r["droop_residual"]," | ",r["thermal_margin"]," | ",r["valid"]," |")
    end
    println(io,"\n| Configuration | Branch active losses (pu) | Shunt active consumption (pu) |\n|---|---:|---:|")
    for r in runs
        m=r["metrics"]
        println(io,"| ",r["name"]," | ",m.branch_active_loss," | ",m.shunt_active_consumption," |")
    end
    println(io,"\n| Configuration / branch | Supplied | Nominal | Solved | Deviation from supplied |\n|---|---:|---:|---:|---:|")
    for r in runs, setting in r["metrics"].settings
        println(io,"| ",r["name"]," / ",setting.branch_id," | ",setting.supplied," | ",setting.nominal," | ",setting.solved," | ",setting.deviation_from_supplied," |")
    end
    println(io,"\n![Tap sweep](tap_sweep.png)\n\n![Operating points](operating_points.png)\n\n![Settings and bounds](tap_settings.png)\n")
    println(io,"Inputs and versioned design results are included. All 41 sweep attempts retain status and validity in evidence.json. Ipopt uses smooth epsilon 1e-5 and the declared `m5_initial_state`; independent tolerances are 1e-6 pu AC balance and 1e-5 pu exact droop. The optimized objective must be no worse than any valid sweep point within 1e-8.\n\nRegression tests check fixed-bound/empty-policy equivalence, policy corruption, unavailable equipment, multiple devices, both-terminal margins, MadNLP agreement and serialization. See [full test log](regression-tests.txt).\n\nRun `julia --project=. examples/m7_1_taps.jl artifacts/m7_1`, then `python3 examples/plot_m7_1_taps.py artifacts/m7_1` with Matplotlib installed. Security-constrained equipment decisions remain M9.")
end
passed || error("M7.1 acceptance failed; inspect retained evidence")
