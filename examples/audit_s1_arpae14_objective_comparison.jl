include("s1_arpae14_objective_comparison.jl")
function audit_objectives()
    base=read_study(joinpath(OC_OUT,"baseline-study.json")).case;_,_,angles,_=gated_inputs();costs,_=oc_costs()
    rows=[JSON.parse(s) for s in readlines(joinpath(OC_OUT,"rows.jsonl"))];@assert length(rows)==90
    n=0
    for r in rows
        haskey(r,"state") || continue
        c=DroopOPF._feasibility_scaled_case(base,r["tags"]["factor"])
        oldcost=r["economic_cost"];oldloss=r["loss_mw"]
        eq_details(c,r,angles,eq_policy(c,"fixed"));oc_metrics!(c,r,costs,r["tags"]["objective"])
        @assert isapprox(oldcost,r["economic_cost"];atol=1e-8)
        @assert isapprox(oldloss,r["loss_mw"];atol=1e-9)
        n+=1
    end
    report=Dict("cells"=>length(rows),"states_replayed"=>n,"verified"=>count(r->r["point_pass"],rows),"accepted"=>count(r->r["accepted"],rows),"mismatches"=>0)
    write(joinpath(OC_OUT,"serialization_audit.json"),JSON.json(report;pretty=true));println(JSON.json(report))
end
audit_objectives()
