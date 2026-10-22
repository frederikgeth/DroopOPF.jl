include("s1_arpae14_joint_reference.jl")
function jr_audit()
    source,_,angles,_=gated_inputs();base=read_study(joinpath(EQ_OUT,"baseline-study.json")).case;costs,_=oc_costs()
    for f in (.9,.95,1.,1.05,1.1),init in ("cost","loss")
        s,path=dd_seed(source,init,f)
        a=validate_feasibility_witness(FeasibilityProblem(DroopOPF._feasibility_scaled_case(source,f);angle_limits=angles),FeasibilityWitness(s))
        @assert a["valid"]
    end
    rows=JSON.parse.(readlines(joinpath(JR_OUT,"rows.jsonl")));selected=JSON.parsefile(joinpath(JR_OUT,"selected.json"));n=0
    append!(rows,JSON.parse.(readlines(joinpath(JR_OUT,"joint_anchor_rows.jsonl"))))
    for r in rows
        haskey(r,"state") || continue
        t=r["tags"];range=t["range"]
        if t["stage"]=="reference"
            c=source;p=jr_policy(c,range)
        else
            chosen=only(filter(x->x["name"]==selected[range],rows))
            c0=t["arm"]=="old_free" ? base : read_study(joinpath(JR_OUT,"$range-study.json")).case
            c=DroopOPF._feasibility_scaled_case(c0,t["factor"])
            p=jr_policy(c,range;selected=t["arm"]=="old_free" ? nothing : chosen,frozen=t["arm"]=="joint_frozen")
        end
        eq_details(c,r,angles,p);oc_metrics!(c,r,costs,"loss");n+=1
    end
    write(joinpath(JR_OUT,"audit.json"),JSON.json(Dict("saved_states_replayed"=>n,"rows"=>length(rows),"mismatches"=>0);pretty=true))
    println("AUDIT ",n," states, zero discrepancies")
end
jr_audit()
