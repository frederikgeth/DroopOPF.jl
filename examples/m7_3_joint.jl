using DroopOPF, JSON
include("m7_2_case.jl")
function m73_workflow(out)
mkpath(out)
c=m72_case();start=m5_initial_state(c)
base=solve_opf(c;smooth_epsilon=1e-5,initial_state=start)
write_study(joinpath(out,"input-study.json"),Study(c))
attempts=[];selected=[]
for t in (false,true), s in (false,true), d in (false,true)
    tag="$(Int(t))$(Int(s))$(Int(d))"; candidates=[]
    for run in 1:2
        taps=t ? [TapControl(11;lower=.95,upper=1.05,initial=run==1 ? 1.02 : 1.)] : TapControl[]
        shunts=s ? [ShuntControl(201;initial=run==1 ? .02 : .04)] : ShuntControl[]
        reference=DroopSettings(c.controls[2])
        initial=DroopSettings(run==1 ? .075 : .095,reference.v_ref,reference.deadband_low,reference.deadband_high)
        droops=d ? [DroopControl(2;slope_bounds=(.04,.1),initial)] : DroopControl[]
        row=Dict{String,Any}("configuration"=>tag,"run"=>run,"tap_free"=>t,"shunt_free"=>s,"droop_free"=>d,
            "start"=>run==1 ? "supplied design / proportional state" : "tap=1, B=.04, slope=.095 / solved fixed state","valid"=>false)
        try
            r=optimize_joint_design(c;tap_controls=taps,shunt_controls=shunts,droop_controls=droops,initial_state=run==1 ? start : base.state)
            check=validate_joint_design(c,r);write_joint_design(joinpath(out,"design-$tag-$run.json"),r)
            row["status"]=string(r.opf.termination_status);row["valid"]=check.valid
            row["policy_valid"]=check.policy_valid;row["solver_valid"]=check.solver_valid
            if !isnothing(r.opf.state)
                m=joint_design_metrics(c,r)
                merge!(row,Dict("objective"=>r.opf.objective,"metrics"=>DroopOPF._json_data(m),
                    "tap"=>r.taps[11],"B"=>get(r.susceptances,201,.02),"slope"=>haskey(r.droops,2) ? r.droops[2].slope : .075,
                    "vm"=>r.opf.state.vm,"qg"=>r.opf.state.qg,
                    "ac_residual"=>isnothing(check.physical) ? nothing : check.physical.power_balance_max,
                    "droop_residual"=>isnothing(check.physical) ? nothing : check.physical.droop_residual_max))
            end
        catch err
            row["error"]=sprint(showerror,err)
        end
        push!(attempts,row);row["valid"] && push!(candidates,row)
    end
    if !isempty(candidates)
        best=deepcopy(candidates[argmin([r["objective"] for r in candidates])])
        best["objective_spread"]=maximum(r["objective"] for r in candidates)-minimum(r["objective"] for r in candidates)
        best["parameter_spread"]=Dict(k=>maximum(r[k] for r in candidates)-minimum(r[k] for r in candidates) for k in ("tap","B","slope"))
        best["valid_starts"]=length(candidates);push!(selected,best)
    end
end
lookup=Dict(r["configuration"]=>r for r in selected)
benefits=[]
for t in 0:1,s in 0:1
    a="$(t)$(s)0";b="$(t)$(s)1"
    haskey(lookup,a) && haskey(lookup,b) && push!(benefits,Dict("equipment"=>"tap=$t shunt=$s","droop_objective_improvement"=>lookup[a]["objective"]-lookup[b]["objective"]))
end
monotonic=true
for (tag,r) in lookup, k in 1:3
    if tag[k]=='0'
        next=collect(tag);next[k]='1';other=String(next)
        haskey(lookup,other) && (monotonic &= lookup[other]["objective"]<=r["objective"]+1e-8)
    end
end
passed=length(selected)==8 && monotonic && all(r["valid"] for r in attempts)
write(joinpath(out,"evidence.json"),JSON.json(Dict("pass"=>passed,"monotonic_within_tolerance"=>monotonic,"attempts"=>attempts,"selected"=>selected,"matched_droop_benefits"=>benefits);pretty=true))
open(joinpath(out,"report.md"),"w") do io
    println(io,"# M7.3 joint equipment and droop design\n\nAcceptance: **",passed ? "PASS" : "FAIL","**. Synthetic three-bus base-case OPF, 100 MVA. Configuration digits are **tap / shunt / droop**, with 1 free and 0 fixed. Each configuration has two declared starts; every attempt, including failures, is retained in evidence.json. The lowest-objective physically valid run is selected and its spread is reported.\n")
    println(io,"Tap 11 bounds: [0.95,1.05]; simple capacitor bank 201 B: [0,0.06] pu with G=0.05B; control 2 slope: [0.04,0.10]. All other equipment and droop settings stay fixed. The bank 202 reactor remains supplied at B=−0.01. Reference and deadband selection are separately covered by regression tests.\n")
    println(io,"| T/S/D | Valid starts | Objective | Tap | B (pu) | Slope | Objective spread | AC residual |\n|---|---:|---:|---:|---:|---:|---:|---:|")
    for r in selected
        println(io,"| ",r["configuration"]," | ",r["valid_starts"],"/2 | ",r["objective"]," | ",r["tap"]," | ",r["B"]," | ",r["slope"]," | ",r["objective_spread"]," | ",r["ac_residual"]," |")
    end
    println(io,"\n| T/S/D | Active-dispatch objective | Reactive-dispatch objective | Branch loss | Shunt consumption | Tap / B / slope spread |\n|---|---:|---:|---:|---:|---|")
    for r in selected
        m=r["metrics"];p=r["parameter_spread"]
        println(io,"| ",r["configuration"]," | ",m["active_dispatch_component"]," | ",m["reactive_dispatch_component"]," | ",m["branch_active_loss"]," | ",m["shunt_active_consumption"]," | ",p["tap"]," / ",p["B"]," / ",p["slope"]," |")
    end
    println(io,"\n| Equipment freedom held fixed | Objective improvement from freeing droop |\n|---|---:|")
    for r in benefits
        println(io,"| ",r["equipment"]," | ",r["droop_objective_improvement"]," |")
    end
    println(io,"\n![Objective components](objectives.png)\n\n![Selected settings](settings.png)\n\n![Operating states](operating_points.png)\n\n![Multi-start spread](multistart.png)\n\n![Matched benefits](matched_benefits.png)\n")
    println(io,"The objective is unchanged: sum of squared active dispatch deviations plus 0.001 times squared reactive deviations. Design penalty is zero in all eight configurations. Losses are metrics, not objective terms. Differences among the four matched droop benefits quantify dependence on equipment freedom; do not add independently measured benefits as though interactions were absent. Similar objectives with differing parameters indicate weak identification on this fixture.\n\nIndependent replay checks exact curves and all equipment at solved settings (AC tolerance 1e-6, droop 1e-5). Smooth epsilon is 1e-5. Added freedom must not worsen the best observed objective by more than 1e-8. These are local continuous solutions, not proof of global optimality, legal bank positions, dynamic performance or SCOPF security.\n\nRun `julia --project=. examples/m7_3_joint.jl artifacts/m7_3`, then `python3 examples/plot_m7_3_joint.py artifacts/m7_3` with Matplotlib installed. See [full regression](regression-tests.txt). M9 adds coordinated equipment SCOPF; complex bank optimization remains behind the scaling gate.")
end
passed || error("M7.3 acceptance failed; retained attempts explain failures")

end
m73_workflow(abspath(ARGS[1]))
