include("s1_arpae14_objective_comparison.jl")
const PC_OUT=joinpath(GATED_ROOT,"artifacts/s1_arpae14_performance_controls")
const PC_FAMILIES=("tap","shunt","tap_shunt","droop","tap_droop","shunt_droop","joint")
pc_policy(c,f)=f in DD_FAMILIES ? dd_policy(c,f) : (;eq_policy(c,f)...,droop_controls=DroopControl[])
function run_performance_controls()
    mkpath(PC_OUT);base=read_study(joinpath(EQ_OUT,"baseline-study.json")).case;source,_,angles,_=gated_inputs();costs,costpath=oc_costs()
    write_study(joinpath(PC_OUT,"baseline-study.json"),Study(base))
    seeds=Dict();checks=[]
    for f in (.9,.95,1.,1.05,1.1),init in ("cost","loss")
        s,path=dd_seed(source,init,f);a=validate_feasibility_witness(FeasibilityProblem(DroopOPF._feasibility_scaled_case(source,f);angle_limits=angles),FeasibilityWitness(s));@assert a["valid"]
        seeds[(init,f)]=s;push!(checks,Dict("factor"=>f,"init"=>init,"valid"=>true,"sha256"=>bytes2hex(sha256(read(path)))))
    end
    write(joinpath(PC_OUT,"precursors.json"),JSON.json(checks;pretty=true))
    inherited=[]
    for line in readlines(joinpath(EQ_OUT,"rows.jsonl"))
        r=JSON.parse(line);r["tags"]["family"]=="fixed" || continue
        c=DroopOPF._feasibility_scaled_case(base,r["tags"]["factor"])
        for family in PC_FAMILIES
            p=pc_policy(c,family)
            for d in p.droop_controls;dp=DroopOPF._joint_droop_policy(c,d);@assert dp.ranges.slope[1]<=c.controls[d.control_id].slope<=dp.ranges.slope[2];end
            a=validate_feasibility_witness(FeasibilityProblem(c;tap_controls=p.tap_controls,shunt_controls=p.shunt_controls,angle_limits=angles),FeasibilityWitness(eq_state(r["state"]);taps=eq_settings(r["taps"]),susceptances=eq_settings(r["susceptances"])));@assert a["valid"]
            push!(inherited,Dict("family"=>family,"witness"=>r["name"],"valid"=>true,"applies_to"=>["cost","loss"]))
        end
    end
    write(joinpath(PC_OUT,"inherited_witnesses.json"),JSON.json(inherited;pretty=true))
    write(joinpath(PC_OUT,"protocol.json"),JSON.json(Dict("families"=>collect(PC_FAMILIES),"objectives"=>["loss","cost"],"design_solves"=>420,"fixed_reused"=>60,"frozen_solves"=>420,"slopes_percent"=>[2,8],"references_deadband"=>"original references fixed; no deadband","tap_bounds"=>"declared +/-5% source study bounds","shunt"=>"available bank3 B=0..0.4 continuous","budget"=>"600 iterations/20 native seconds; smooth voltage and absolute Q widths1e-6; tight CCOpt","selection"=>"best accepted nominal design per objective/family by independently evaluated objective, then name","frozen"=>"all settings frozen then evaluated under selection objective across five demands; no retuning","cost_scale"=>OC_COST_SCALE,"cost_sha256"=>bytes2hex(sha256(read(costpath))));pretty=true))
    ledger=joinpath(PC_OUT,"design_rows.jsonl")
    if !isfile(ledger)
        open(ledger,"w") do io
            for line in readlines(joinpath(OC_OUT,"rows.jsonl"))
                r=JSON.parse(line);r["tags"]["objective"]=="dispatch" && continue
                r["name"]="fixed-"*r["name"];r["reused_from"]="artifacts/s1_arpae14_objective_comparison/rows.jsonl";println(io,JSON.json(r))
            end
        end
    end
    rows=[JSON.parse(s) for s in readlines(ledger)];done=Set(r["name"] for r in rows)
    for objective in ("loss","cost"),family in PC_FAMILIES,f in (.9,.95,1.,1.05,1.1),init in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
        name="$objective-$family-$f-$init-$solver";name in done && continue
        c=DroopOPF._feasibility_scaled_case(base,f);s=seeds[(init,f)]
        r=dd_cell(c,s,angles,solver,family,name;policy=pc_policy(c,family),out=PC_OUT,objective_hook=oc_hook(c,s,costs,objective))
        r["tags"]=Dict("family"=>family,"objective"=>objective,"factor"=>f,"initialization_objective"=>init)
        oc_metrics!(c,r,costs,objective)
        open(ledger,"a") do io;println(io,JSON.json(r));end;push!(rows,r)
        println("PERFORMANCE ",length(rows),"/480 ",name," accepted=",r["accepted"]);flush(stdout)
    end
    @assert length(rows)==480
    ledger=joinpath(PC_OUT,"frozen_rows.jsonl");fr=isfile(ledger) ? [JSON.parse(s) for s in readlines(ledger)] : Any[];done=Set(r["name"] for r in fr);selected=[]
    for objective in ("loss","cost"),family in PC_FAMILIES
        candidates=filter(r->r["tags"]["objective"]==objective && r["tags"]["family"]==family && r["tags"]["factor"]==1. && r["accepted"],rows)
        isempty(candidates) && error("no nominal candidate $objective $family")
        chosen=first(sort(candidates;by=r->(r["objective_recomputed"],r["name"])))
        result=read_joint_design(joinpath(PC_OUT,chosen["name"]*"-result.json"));frozen=with_joint_settings(base,result)
        path=joinpath(PC_OUT,"$objective-$family-frozen-study.json");write_study(path,Study(frozen))
        a=validate_feasibility_witness(FeasibilityProblem(frozen;angle_limits=angles),FeasibilityWitness(result.opf.state));@assert a["valid"]
        push!(selected,Dict("family"=>family,"objective"=>objective,"source"=>chosen["name"],"sha256"=>bytes2hex(sha256(read(path))),"slopes_percent"=>chosen["slopes_percent"],"nominal_witness"=>true))
        for f in (.9,.95,1.,1.05,1.1),init in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
            name="frozen-$objective-$family-$f-$init-$solver";name in done && continue
            c=DroopOPF._feasibility_scaled_case(frozen,f);s=seeds[(init,f)]
            tags=Dict("family"=>family,"objective"=>objective,"factor"=>f,"initialization_objective"=>init,"selected_design"=>chosen["name"])
            r=js_cell(c,s,angles,solver,tags;reactive_epsilon=1e-6,objective_hook=oc_hook(c,s,costs,objective));r["name"]=name
            eq_details(c,r,angles,eq_policy(c,"fixed"));oc_metrics!(c,r,costs,objective)
            open(ledger,"a") do io;println(io,JSON.json(r));end;push!(fr,r)
            println("FROZEN ",length(fr),"/420 ",name," accepted=",r["accepted"]);flush(stdout)
        end
    end
    @assert length(fr)==420
    write(joinpath(PC_OUT,"selected_designs.json"),JSON.json(selected;pretty=true))
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_performance_controls()
