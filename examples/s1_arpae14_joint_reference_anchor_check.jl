include("s1_arpae14_joint_reference.jl")
function jr_anchor_check()
    source,_,angles,_=gated_inputs();costs,_=oc_costs();rows=JSON.parse.(readlines(joinpath(JR_OUT,"rows.jsonl")));selected=JSON.parsefile(joinpath(JR_OUT,"selected.json"))
    protocol=JSON.parsefile(joinpath(JR_OUT,"protocol.json"))
    protocol["additional_anchor_check"]="90 solves from nominal jointly optimized reference; same policies/objectives/budgets; separate from matched source starts"
    protocol["primary_solve_count"]=258;protocol["additional_solve_count"]=90
    protocol["reference_solver_note"]="No complementarity in source OPF: CCOpt falls back to MadNLP; downstream droop models use complementarity"
    write(joinpath(JR_OUT,"protocol.json"),JSON.json(protocol;pretty=true))
    ledger=joinpath(JR_OUT,"joint_anchor_rows.jsonl");done=isfile(ledger) ? Set(JSON.parse(l)["name"] for l in readlines(ledger)) : Set()
    for range in ("relative5","relative10","absolute10")
        chosen=only(filter(x->x["name"]==selected[range],rows));start=eq_state(chosen["state"]);base=read_study(joinpath(JR_OUT,"$range-study.json")).case
        for arm in ("joint_frozen","joint_free"),f in (.9,.95,1.,1.05,1.1),solver in (:ipopt,:madnlp,:ccopt)
            name="$arm-$range-$f-joint_anchor-$solver";name in done && continue
            c=DroopOPF._feasibility_scaled_case(base,f);p=jr_policy(c,range;selected=chosen,frozen=arm=="joint_frozen")
            tags=Dict("stage"=>"evaluation","range"=>range,"arm"=>arm,"factor"=>f,"init"=>"nominal_joint_reference")
            r=js_cell(c,start,angles,solver,tags;p...,reactive_epsilon=1e-6,objective_hook=oc_hook(c,start,costs,"loss"));r["name"]=name
            eq_details(c,r,angles,p);oc_metrics!(c,r,costs,"loss")
            open(ledger,"a") do io;println(io,JSON.json(r));end
            println(name," accepted=",r["accepted"]);flush(stdout)
        end
    end
end
jr_anchor_check()
