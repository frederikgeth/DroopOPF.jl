include("s1_arpae14_performance_controls.jl")
function audit_performance()
    base=read_study(joinpath(PC_OUT,"baseline-study.json")).case;_,_,angles,_=gated_inputs();costs,_=oc_costs();summary=Dict()
    for mode in ("design","frozen")
        rows=[JSON.parse(s) for s in readlines(joinpath(PC_OUT,"$(mode)_rows.jsonl"))];@assert length(rows)==(mode=="design" ? 480 : 420)
        checked=0
        for r in rows
            haskey(r,"state") || continue
            f=r["tags"]["factor"];family=r["tags"]["family"];objective=r["tags"]["objective"]
            if mode=="design"
                c=DroopOPF._feasibility_scaled_case(base,f)
                if family=="fixed"
                    curve=c;p=eq_policy(c,"fixed")
                else
                    result=read_joint_design(joinpath(PC_OUT,r["name"]*"-result.json"));check=validate_joint_design(c,result);@assert check.policy_valid==r["policy_valid"]
                    curve=DroopOPF._joint_droop_case(c,result);policy=pc_policy(c,family);p=(tap_controls=policy.tap_controls,shunt_controls=policy.shunt_controls)
                end
            else
                c=DroopOPF._feasibility_scaled_case(read_study(joinpath(PC_OUT,"$objective-$family-frozen-study.json")).case,f);curve=c;p=eq_policy(c,"fixed")
            end
            cost=r["economic_cost"];loss=r["loss_mw"]
            eq_details(curve,r,angles,p);oc_metrics!(c,r,costs,objective)
            @assert isapprox(cost,r["economic_cost"];atol=1e-8) && isapprox(loss,r["loss_mw"];atol=1e-9)
            checked+=1
        end
        summary[mode]=Dict("cells"=>length(rows),"replayed"=>checked,"verified"=>count(r->r["point_pass"],rows),"accepted"=>count(r->r["accepted"],rows),"mismatches"=>0)
    end
    write(joinpath(PC_OUT,"serialization_audit.json"),JSON.json(summary;pretty=true));println(JSON.json(summary))
end
audit_performance()
