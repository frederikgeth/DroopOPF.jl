using DroopOPF, JSON
include("m7_2_case.jl")
out=abspath(ARGS[1]);mkpath(out)
sweeps=[];runs=[]
for cap in (true,false)
    c=m72_case(capacitor=cap);name=cap ? "capacitor" : "reactor";start=m5_initial_state(c)
    write_study(joinpath(out,"$name-study.json"),Study(c))
    for B in range(cap ? 0. : -.06,cap ? .06 : 0.;length=31)
        physical=with_shunt_settings(c,Dict(201=>B))
        r=solve_opf(physical;smooth_epsilon=1e-5,initial_state=start)
        valid=!isnothing(r.state) && validate_equilibrium(physical,r).valid
        push!(sweeps,Dict("equipment"=>name,"B"=>B,"objective"=>r.objective,"valid"=>valid,"status"=>string(r.termination_status)))
    end
    for (mode,controls) in (("fixed",ShuntControl[]),("one free",[ShuntControl(201)]),("both free",[ShuntControl(201),ShuntControl(202)]))
        r=optimize_shunts(c,controls;initial_state=start);check=validate_shunt_design(c,r)
        write_shunt_design(joinpath(out,"$name-$(length(controls))-design.json"),r)
        physical=with_shunt_settings(c,r.susceptances)
        total= sum(shunt_powers(physical.network,r.opf.state))+sum(bank_powers(physical.network,r.opf.state))
        push!(runs,Dict("equipment"=>name,"mode"=>mode,"valid"=>check.valid,
            "status"=>string(r.opf.termination_status),"objective"=>r.opf.objective,
            "settings"=>r.susceptances,"vm"=>r.opf.state.vm,"qg"=>r.opf.state.qg,
            "reactive_support"=>-imag(total),"metrics"=>shunt_design_metrics(c,r),
            "ac_residual"=>check.physical.power_balance_max,"droop_residual"=>check.physical.droop_residual_max))
    end
end
passed=all(r["valid"] for r in sweeps) && all(r["valid"] for r in runs) && all(
    r["objective"]<=minimum(s["objective"] for s in sweeps if s["equipment"]==r["equipment"])+1e-8
    for r in runs if r["mode"]=="one free")
write(joinpath(out,"evidence.json"),JSON.json(Dict("pass"=>passed,"sweeps"=>sweeps,"runs"=>runs);pretty=true))
open(joinpath(out,"report.md"),"w") do io
    println(io,"# M7.2 simple capacitor/reactor optimization\n\nNumerical acceptance: **",passed ? "PASS" : "FAIL","**. Synthetic three-bus base-case OPF, 100 MVA. Transformer ratios, phase shifts and droop settings remain fixed.\n")
    println(io,"Bank 201 at bus 30 has step G=0.001 pu and B=+0.02 (capacitor) or −0.02 (reactor), legal counts 0–3, supplied/nominal count 1. Bank 202 at bus 20 has G=0.0005, B=−0.01, legal counts 0–2 and supplied/nominal count 1. Fixed shunt 101 is retained. The fractional count scales both G and B; no independent conductance freedom is added.\n")
    println(io,"| Equipment / mode | Objective | AC residual | Exact droop residual | Valid |\n|---|---:|---:|---:|---|")
    for r in runs
        println(io,"| ",r["equipment"]," / ",r["mode"]," | ",r["objective"]," | ",r["ac_residual"]," | ",r["droop_residual"]," | ",r["valid"]," |")
    end
    println(io,"\n| Equipment / mode | Branch active losses | Shunt active consumption | Net shunt reactive injection |\n|---|---:|---:|---:|")
    for r in runs
        m=r["metrics"]
        println(io,"| ",r["equipment"]," / ",r["mode"]," | ",m.branch_active_loss," | ",m.shunt_active_consumption," | ",r["reactive_support"]," |")
    end
    println(io,"\n| Equipment / mode / bank | Supplied B | Nominal B | Solved B | Solved G | Fractional count |\n|---|---:|---:|---:|---:|---:|")
    for r in runs, s in r["metrics"].settings
        println(io,"| ",r["equipment"]," / ",r["mode"]," / ",s.bank_id," | ",s.supplied," | ",s.nominal," | ",s.solved," | ",s.conductance," | ",s.fractional_count," |")
    end
    println(io,"\n![Susceptance sweep](susceptance_sweep.png)\n\n![Voltages and reactive support](operating_points.png)\n\n![Simple bank relaxation](bank_envelopes.png)\n\n![Active losses](active_losses.png)\n")
    println(io,"All powers and admittances are pu. Positive reactive support means injection. The baseline dispatch-deviation objective is unchanged; loss and setting metrics are not objective terms. These are local continuous relaxed solutions, not legal switching positions or global optimality certificates.\n\nEach 31-point sweep retains solver status and physical validity. Both optimized single-bank objectives match or improve every sweep point within 1e-8. Ipopt uses smoothing 1e-5 and declared `m5_initial_state` starts; independent AC and exact-droop tolerances are 1e-6 and 1e-5 pu. Regression additionally covers fixed-bound equivalence, reactor signs, G/B coupling, voltage-squared scaling, multiple banks, invalid policies, preservation, MadNLP and result round trips. See [regression log](regression-tests.txt).\n\nRun `julia --project=. examples/m7_2_shunts.jl artifacts/m7_2`, followed by `python3 examples/plot_m7_2_shunts.py artifacts/m7_2` with Matplotlib installed. Heterogeneous-bank optimization is deferred until the simple bank/transformer/droop scaling gate passes. Joint equipment/droop optimization remains M7.3 and optimized SCOPF coupling M9.")
end
passed || error("M7.2 acceptance failed")
