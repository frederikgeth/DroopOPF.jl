# Follow-up experiments retain every primary failure and use the same physical acceptance rules.
include("s1_arpae14_stress.jl")
function a14_followup(out)
    c,source,n=a14_case();cc,p=a14_overlay(c,source)
    primary=JSON.parsefile(joinpath(out,"summary.json")); dest=joinpath(out,"followup");mkpath(dest)
    rows=isfile(joinpath(dest,"summary.json")) ? JSON.parsefile(joinpath(dest,"summary.json")) : Any[]
    function run(name,case,start,solver,policies;block,profile=:tight)
        any(r->r["name"]==name,rows) && return
        tags=Dict("block"=>block,"profile"=>string(profile))
        row,result=solver==:ccopt ? s1_ccopt_attempt(dest,name,case,start;policies,tags,option_overrides=merge(s1_ccopt_profile(profile),Dict{String,Any}("max_iter"=>3000,"max_wall_time"=>30.))) : s1_attempt(dest,name,case,start;policies,solver,tags,options=solver==:ipopt ? Dict{String,Any}("max_iter"=>3000,"max_cpu_time"=>30.) : Dict{String,Any}("max_iter"=>3000,"max_wall_time"=>30.))
        row["solver"]=string(solver);row["budget"]=Dict("iterations"=>3000,"native_seconds"=>30.)
        if result!==nothing && result.opf.state!==nothing
            phys=with_joint_settings(case,result);st=result.opf.state;idx=Dict(b.id=>i for (i,b) in enumerate(phys.network.buses))
            row["source_angle_violation_rad"]=maximum(max(n["branch"][string(b.id)]["angmin"]-(st.va[idx[b.from_bus]]-st.va[idx[b.to_bus]]),(st.va[idx[b.from_bus]]-st.va[idx[b.to_bus]])-n["branch"][string(b.id)]["angmax"],0.) for b in phys.network.branches if b.available)
            row["valid"]=get(row,"valid",false) && row["source_angle_violation_rad"]<=1e-5
            row["metrics"]=DroopOPF._json_data(joint_design_metrics(case,result))
            replay=read_joint_design(joinpath(dest,name*"-design.json"))
            row["serialization_replay_valid"]=validate_joint_design(case,replay).valid
            row["valid"]=row["valid"] && row["serialization_replay_valid"]
        end
        write(joinpath(dest,name*"-diagnostics.json"),JSON.json(row;pretty=true));push!(rows,row);s1_summary(dest,rows)
    end
    empty=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
    for mode in (:anchor,)
        run("baseline-ccopt-$mode",c,a14_start(c,source,mode),:ccopt,empty;block="baseline_diagnostics_fix")
    end
    full=(tap_controls=p.tap_controls,shunt_controls=p.shunt_controls,droop_controls=[DroopControl(i;slope_bounds=(.5*d.slope,2*d.slope),v_ref_bounds=(source.vm[findfirst(b->b.id==cc.attachments[i].location.bus_id,cc.network.buses)]-.01,source.vm[findfirst(b->b.id==cc.attachments[i].location.bus_id,cc.network.buses)]+.01),deadband_low_bounds=(.002,.01),deadband_high_bounds=(.002,.01)) for (i,d) in enumerate(cc.controls)])
    for solver in (:ipopt,:madnlp,:ccopt),mode in (:anchor,)
        policies=mode==:anchor ? full : s1_reseed(cc,full;fraction=mode==:flat_low ? .2 : .8)
        run("full-droop-$solver-$mode",cc,a14_start(cc,source,mode),solver,policies;block="all_droop_parameters")
    end
    for family in S1_CCOPT_FAMILIES
        candidates=filter(r->r["valid"] && r["tags"]["block"]=="matrix" && r["tags"]["family"]==string(family) && r["tags"]["load_factor"]==1.,primary)
        # A failed family still gets a source-state larger-budget retry.
        best=isempty(candidates) ? nothing : read_joint_design(joinpath(out,first(sort(candidates;by=r->r["objective"]))["name"]*"-design.json"))
        policies=s1_ccopt_family(p,family;count=100)
        best===nothing || (policies=s1_reseed(cc,policies;result=best))
        start=best===nothing ? source : best.opf.state
        for solver in (:ipopt,:madnlp,:ccopt)
            run("recovery-$family-$solver",cc,start,solver,policies;block=best===nothing ? "larger_budget_source" : "accepted_solution_warm_start")
        end
        run("standard-$family-ccopt",cc,start,:ccopt,policies;block="ccopt_standard_profile",profile=:standard)
    end
    println("FOLLOWUP COMPLETE ",length(rows)," accepted ",Base.count(r->get(r,"valid",false),rows))
end
abspath(PROGRAM_FILE)==(@__FILE__) && a14_followup(abspath(joinpath(@__DIR__,"..","artifacts","s1_arpae14_stress")))
