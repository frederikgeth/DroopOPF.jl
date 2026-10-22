include("s1_arpae14_performance_controls.jl")
const OL_OUT=joinpath(GATED_ROOT,"artifacts/s1_arpae14_original_limits")
function ol_inputs()
    path=joinpath(GATED_ROOT,"test/data/arpae/c1_network01/results/scenario_01/network_model.json")
    original=JSON.parsefile(path);@assert count(b->b["bus_type"]!=4,values(original["bus"]))==14 && length(original["gen"])==6
    original,path
end
function ol_check(c,s,original,variant)
    violations=[];margins=[]
    for (i,g) in enumerate(c.generators)
        g.available || continue
        o=original["gen"][string(g.id)];@assert o["gen_status"]==1 && o["gen_bus"]==g.bus_id
        for axis in (variant=="original_p" ? ("p",) : variant=="original_q" ? ("q",) : ("p","q"))
            val=axis=="p" ? s.pg[i] : s.qg[i];lo=o[axis*"min"];hi=o[axis*"max"]
            push!(margins,Dict("generator"=>g.id,"axis"=>axis,"value"=>val,"min"=>lo,"max"=>hi,"lower_margin"=>val-lo,"upper_margin"=>hi-val))
            val<lo-1e-6 && push!(violations,"g$(g.id)_$(axis)min")
            val>hi+1e-6 && push!(violations,"g$(g.id)_$(axis)max")
        end
    end
    Dict("valid"=>isempty(violations),"violations"=>violations,"margins"=>margins)
end
function ol_hook(c,start,costs,objective,original,variant)
    objectivehook=oc_hook(c,start,costs,objective)
    function hook(phase,model)
        phase==:built || return
        for (i,g) in enumerate(c.generators)
            g.available || continue
            o=original["gen"][string(g.id)]
            for axis in (variant=="original_p" ? ("p",) : variant=="original_q" ? ("q",) : ("p","q"))
                x=variable_by_name(model,"$(axis)g[$i]")
                set_lower_bound(x,max(lower_bound(x),o[axis*"min"]))
                set_upper_bound(x,min(upper_bound(x),o[axis*"max"]))
            end
        end
        objectivehook(phase,model)
    end
end
function ol_candidates()
    items=[("reference_loss","loss",read_study(joinpath(EQ_OUT,"baseline-study.json")).case),
           ("reference_cost","cost",read_study(joinpath(EQ_OUT,"baseline-study.json")).case)]
    manifest=JSON.parsefile(joinpath(PC_OUT,"carried_forward_candidates.json"))
    for item in manifest["candidates"]
        path=joinpath(GATED_ROOT,item["frozen_case"]);@assert bytes2hex(sha256(read(path)))==item["sha256"]
        push!(items,(item["objective"]*"_"*item["family"],item["objective"],read_study(path).case))
    end
    items
end
function ol_prior(name,objective)
    if startswith(name,"reference_")
        rs=[JSON.parse(s) for s in readlines(joinpath(OC_OUT,"rows.jsonl"))]
        return filter(r->r["tags"]["objective"]==objective,rs)
    end
    family=replace(name,objective*"_"=>"";count=1)
    rs=[JSON.parse(s) for s in readlines(joinpath(PC_OUT,"frozen_rows.jsonl"))]
    filter(r->r["tags"]["objective"]==objective && r["tags"]["family"]==family,rs)
end
function run_original_limits()
    mkpath(OL_OUT);original,path=ol_inputs();source,_,angles,_=gated_inputs();costs,_=oc_costs();candidates=ol_candidates();seeds=Dict();precursors=[]
    for variant in ("original_p","original_q","original_pq"),objective in ("cost","loss"),f in (.9,.95,1.,1.05,1.1)
        seedpath=joinpath(OL_OUT,"opf-$variant-$objective-$f.json");sol=JSON.parsefile(seedpath)["solution"]
        s=ACState([sol["bus"][string(b.id)]["vm"] for b in source.network.buses],[sol["bus"][string(b.id)]["va"] for b in source.network.buses],
            [get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"] for g in source.generators],[get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"] for g in source.generators])
        c=DroopOPF._feasibility_scaled_case(source,f)
        a=validate_feasibility_witness(FeasibilityProblem(c;angle_limits=angles),FeasibilityWitness(s));limits=ol_check(c,s,original,variant)
        @assert a["valid"] && limits["valid"]
        seeds[(variant,objective,f)]=s;push!(precursors,Dict("variant"=>variant,"objective"=>objective,"factor"=>f,"valid"=>true,"seed_sha256"=>bytes2hex(sha256(read(seedpath)))))
    end
    write(joinpath(OL_OUT,"precursors.json"),JSON.json(precursors;pretty=true))
    replay=[]
    for (name,obj,c) in candidates
        write_study(joinpath(OL_OUT,"$name-study.json"),Study(c))
        for r in ol_prior(name,obj)
            r["point_pass"] || continue
            for variant in ("original_p","original_q","original_pq")
                a=ol_check(c,eq_state(r["state"]),original,variant)
                push!(replay,Dict("candidate"=>name,"variant"=>variant,"source"=>r["name"],"factor"=>r["tags"]["factor"],"limits"=>a))
            end
        end
    end
    write(joinpath(OL_OUT,"prior_point_replay.json"),JSON.json(replay;pretty=true))
    write(joinpath(OL_OUT,"protocol.json"),JSON.json(Dict("cells"=>450,"source_opfs"=>30,"candidates"=>[x[1] for x in candidates],"variants"=>["original_p","original_q","original_pq"],"original_limits_sha256"=>bytes2hex(sha256(read(path))),"original_generators"=>original["gen"],"curve_policy"=>"exact original study curves retained, including saturation; only generator operating bounds tightened as intersection; no clipping/recalibration/redesign","case_representation"=>"serialized original study case plus explicit original-limit overlay in this protocol; validity requires base physical audit AND overlay audit","initialization"=>"fresh demand-matched cost/loss source OPFs for each limit variant","objectives"=>"loss for reference_loss/loss_tap_droop; cost for remaining candidates","budget"=>"600 iterations/20 native seconds; smooth voltage/absolute Q epsilon1e-6; tight CCOpt","equipment"=>"all candidate taps/shunts fixed","offline"=>"G6 stays offline; no positive Pmin imposed on offline output");pretty=true))
    ledger=joinpath(OL_OUT,"rows.jsonl");rows=isfile(ledger) ? [JSON.parse(s) for s in readlines(ledger)] : Any[];done=Set(r["name"] for r in rows)
    for (name,objective,base) in candidates,variant in ("original_p","original_q","original_pq"),f in (.9,.95,1.,1.05,1.1),init in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
        id="$name-$variant-$f-$init-$solver";id in done && continue
        c=DroopOPF._feasibility_scaled_case(base,f);start=seeds[(variant,init,f)]
        tags=Dict("candidate"=>name,"objective"=>objective,"variant"=>variant,"factor"=>f,"initialization_objective"=>init)
        r=js_cell(c,start,angles,solver,tags;reactive_epsilon=1e-6,objective_hook=ol_hook(c,start,costs,objective,original,variant));r["name"]=id
        eq_details(c,r,angles,eq_policy(c,"fixed"));oc_metrics!(c,r,costs,objective)
        r["study_point_pass"]=r["point_pass"]
        if haskey(r,"state")
            a=ol_check(c,eq_state(r["state"]),original,variant);r["original_limit_checks"]=a
            r["point_pass"] &= a["valid"];r["accepted"]=r["point_pass"] && r["solver_success"]
        end
        r["gate_status"]=r["point_pass"] ? "feasible" : "unresolved"
        open(ledger,"a") do io;println(io,JSON.json(r));end;push!(rows,r)
        println("ORIGINAL ",length(rows),"/450 ",id," accepted=",r["accepted"]);flush(stdout)
    end
    @assert length(rows)==450
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_original_limits()
