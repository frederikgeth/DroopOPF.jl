include("s1_arpae14_original_limits.jl")
function audit_original_limits()
    original,_=ol_inputs();_,_,angles,_=gated_inputs();costs,_=oc_costs()
    rows=[JSON.parse(s) for s in readlines(joinpath(OL_OUT,"rows.jsonl"))];@assert length(rows)==450
    cases=Dict();checked=0
    for r in rows
        haskey(r,"state") || continue
        name=r["tags"]["candidate"];variant=r["tags"]["variant"]
        if !haskey(cases,name);cases[name]=read_study(joinpath(OL_OUT,"$name-study.json")).case;end
        c=DroopOPF._feasibility_scaled_case(cases[name],r["tags"]["factor"])
        recorded=r["point_pass"];r["point_pass"]=r["study_point_pass"]
        eq_details(c,r,angles,eq_policy(c,"fixed"))
        a=ol_check(c,eq_state(r["state"]),original,variant)
        @assert (r["point_pass"] && a["valid"])==recorded
        @assert a["valid"]==r["original_limit_checks"]["valid"]
        oc_metrics!(c,r,costs,r["tags"]["objective"])
        r["point_pass"]=recorded;checked+=1
    end
    summary=Dict("cells"=>length(rows),"states_replayed"=>checked,"verified"=>count(r->r["point_pass"],rows),"accepted"=>count(r->r["accepted"],rows),"mismatches"=>0)
    write(joinpath(OL_OUT,"serialization_audit.json"),JSON.json(summary;pretty=true));println(JSON.json(summary))
end
audit_original_limits()
