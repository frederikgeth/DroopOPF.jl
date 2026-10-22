include("s1_arpae14_droop_design.jl")
function audit_droop_design()
    base=read_study(joinpath(DD_OUT,"baseline-study.json")).case;_,_,angles,_=gated_inputs();counts=Dict()
    for mode in ("design","frozen")
        rows=[JSON.parse(s) for s in readlines(joinpath(DD_OUT,"$(mode)_rows.jsonl"))];@assert length(rows)==120
        replayed=0
        for r in rows
            family=r["tags"]["family"];factor=r["tags"]["factor"]
            haskey(r,"state") || continue
            if mode=="design"
                c=DroopOPF._feasibility_scaled_case(base,factor)
                result=read_joint_design(joinpath(DD_OUT,r["name"]*"-result.json"))
                check=validate_joint_design(c,result);@assert check.policy_valid==r["policy_valid"]
                curve=DroopOPF._joint_droop_case(c,result);p=dd_policy(c,family)
                eq_details(curve,r,angles,(tap_controls=p.tap_controls,shunt_controls=p.shunt_controls))
            else
                frozen=read_study(joinpath(DD_OUT,"$family-frozen-study.json")).case
                c=DroopOPF._feasibility_scaled_case(frozen,factor);eq_details(c,r,angles,eq_policy(c,"fixed"))
            end
            replayed+=1
        end
        counts[mode]=Dict("cells"=>length(rows),"replayed"=>replayed,"verified"=>count(r->r["point_pass"],rows),"accepted"=>count(r->r["accepted"],rows),"mismatches"=>0)
    end
    write(joinpath(DD_OUT,"serialization_audit.json"),JSON.json(counts;pretty=true));println(JSON.json(counts))
end
audit_droop_design()
