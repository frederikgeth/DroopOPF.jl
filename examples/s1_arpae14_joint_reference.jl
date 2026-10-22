# Joint loss reference ablation. S1 only; no contingencies or flat starts.
include("s1_arpae14_objective_comparison.jl")
const JR_OUT=joinpath(GATED_ROOT,"artifacts/s1_arpae14_joint_reference")
function jr_policy(c,range;selected=nothing,frozen=false)
    taps=TapControl[]
    for b in c.network.branches
        b.available && b.kind==:transformer || continue
        lo,hi=range=="absolute10" ? (.9,1.1) : range=="relative10" ? (.9*b.tap_ratio,1.1*b.tap_ratio) : (.95*b.tap_ratio,1.05*b.tap_ratio)
        initial=isnothing(selected) ? b.tap_ratio : selected["taps"][string(b.id)]
        frozen && ((lo,hi)=(initial,initial))
        push!(taps,TapControl(b.id;lower=lo,upper=hi,initial,nominal=b.tap_ratio))
    end
    shunts=ShuntControl[]
    for b in c.network.banks
        b.available || continue
        initial=isnothing(selected) ? 0. : selected["susceptances"][string(b.id)]
        push!(shunts,ShuntControl(b.id;lower=frozen ? initial : 0.,upper=frozen ? initial : .4,initial))
    end
    (tap_controls=taps,shunt_controls=shunts)
end
function jr_run()
    mkpath(JR_OUT);source,_,angles,_=gated_inputs();base=read_study(joinpath(EQ_OUT,"baseline-study.json")).case;costs,_=oc_costs()
    seeds=Dict((init,f)=>first(dd_seed(source,init,f)) for init in ("cost","loss") for f in (.9,.95,1.,1.05,1.1))
    write(joinpath(JR_OUT,"protocol.json"),JSON.json(Dict("scope"=>"S1 only; pmin0 symmetric Q; nominal 100% loss reference; fixed uniform8 no deadband", "ranges"=>["relative5","relative10","absolute10"],"relative_center"=>"imported source operating tap; bounds never recentered", "shunt"=>"available bank3 continuous B 0..0.4; fixed shunts unchanged", "objective"=>"loss in both reference OPF and downstream droop OPF", "starts"=>"same demand-matched saved cost and loss source OPFs for every evaluation; no flat starts", "demands"=>[.9,.95,1.,1.05,1.1],"solvers"=>["ipopt","madnlp","ccopt"],"budget"=>"600 iterations/20 solver seconds per cell", "movement"=>"no additional budget; independent S1 demand solves; frozen arm uses exact equality bounds", "comparison"=>"old calibration free tap/shunt vs joint calibration free tap/shunt with identical bounds; joint frozen vs old fixed" );pretty=true))
    ledger=joinpath(JR_OUT,"rows.jsonl");rows=isfile(ledger) ? JSON.parse.(readlines(ledger)) : Any[]
    function cell(c,s,p,tags,name,solver)
        old=findfirst(r->r["name"]==name,rows);isnothing(old) || return rows[old]
        r=js_cell(c,s,angles,solver,tags;p...,reactive_epsilon=1e-6,objective_hook=oc_hook(c,s,costs,"loss"));r["name"]=name
        eq_details(c,r,angles,p);oc_metrics!(c,r,costs,"loss")
        open(ledger,"a") do io;println(io,JSON.json(r));end;push!(rows,r)
        println("JOINTREF ",length(rows)," ",name," accepted=",r["accepted"]," error=",get(r,"error",""));flush(stdout);r
    end
    selected=Dict();checks=[]
    for range in ("relative5","relative10","absolute10")
        p=jr_policy(source,range);refs=[]
        for init in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
            tags=Dict("stage"=>"reference","range"=>range,"factor"=>1.,"init"=>init)
            push!(refs,cell(source,seeds[(init,1.)],p,tags,"ref-$range-$init-$solver",solver))
        end
        good=filter(r->r["accepted"],refs);isempty(good) && error("no accepted reference $range")
        chosen=first(sort(good;by=r->(r["loss_mw"],r["name"])));selected[range]=chosen["name"]
        anchor=eq_state(chosen["state"]);new=js_case(base,anchor,"zero_q_shifted",fill(8.,5),0.,"joint-reference-$range")
        write_study(joinpath(JR_OUT,"$range-study.json"),Study(new))
        pfix=jr_policy(new,range;selected=chosen,frozen=true)
        a=validate_feasibility_witness(FeasibilityProblem(new;pfix...,angle_limits=angles),FeasibilityWitness(anchor;taps=eq_settings(chosen["taps"]),susceptances=eq_settings(chosen["susceptances"])))
        @assert a["valid"];push!(checks,Dict("range"=>range,"selected"=>chosen["name"],"nominal_droop_calibration_replay"=>DroopOPF._json_data(a)))
        for arm in ("joint_frozen","joint_free","old_free")
            # Existing relative5 old-free runs are reused in the report.
            arm=="old_free" && range=="relative5" && continue
            c0=arm=="old_free" ? base : new
            p=jr_policy(c0,range;selected=arm=="old_free" ? nothing : chosen,frozen=arm=="joint_frozen")
            for f in (.9,.95,1.,1.05,1.1),init in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
                c=DroopOPF._feasibility_scaled_case(c0,f);s=seeds[(init,f)]
                tags=Dict("stage"=>"evaluation","arm"=>arm,"range"=>range,"factor"=>f,"init"=>init,"reference"=>chosen["name"])
                cell(c,s,p,tags,"$arm-$range-$f-$init-$solver",solver)
            end
        end
    end
    write(joinpath(JR_OUT,"selected.json"),JSON.json(selected;pretty=true));write(joinpath(JR_OUT,"precursors.json"),JSON.json(checks;pretty=true))
    @assert length(rows)==258
    println("COMPLETE ",length(rows));flush(stdout)
end
abspath(PROGRAM_FILE)==(@__FILE__) && jr_run()
