# Optional HiGHS environment. Fixed-control S1 only; no SCOPF campaign.
using DroopOPF, HiGHS
const CycleJSON=DroopOPF.JSON
include("global_feasibility_scale_probe.jl")

function run_cycle_feasibility(;time_limit=60.)
    root=normpath(joinpath(@__DIR__,".."));out=joinpath(root,"artifacts","s1_cycle_feasibility");mkpath(out)
    conditions=CycleJSON.parsefile(joinpath(root,"artifacts","s1_arpae14_feasibility_gate","no_deadband-qualification.json"))["data"]["conditions"]
    angles=Dict(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in conditions["source/0.9"]["problem"]["angle_limits_rad"])
    rows=[]
    for variant in ("no_deadband","with_deadband")
        c=read_study(joinpath(root,"artifacts","s1_arpae14_corrected_comparison","verified",variant*"-study.json")).case
        p=FeasibilityProblem(DroopOPF._feasibility_scaled_case(c,.9);angle_limits=angles)
        println("CYCLE START ",variant);flush(stdout)
        r=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit,max_rounds=100,
            psd_clique_limit=8,bound_tightening_rounds=3,bound_cut_rounds=8)
        write_feasibility_result(joinpath(out,variant*".json"),p,r)
        # Exercise persisted proof reconstruction, including all bound stages.
        loaded=read_feasibility_result(joinpath(out,variant*".json"),p)
        verified_feasibility_voltage_bounds(p,loaded)
        a=only(r.attempts)
        push!(rows,Dict("case"=>"14-bus 90% $variant","status"=>string(r.status),
            "seconds"=>a["elapsed_seconds"],"variables"=>a["variables"],"rows"=>a["rows"],
            "cliques"=>a["psd_cliques"],"lifted_edges"=>a["lifted_edges"],
            "psd_cuts"=>a["psd_cuts"]+sum(count(c->c["kind"]=="psd",s["cuts"]) for s in a["verified_bound_stages"];init=0),
            "bound_stages"=>length(a["verified_bound_stages"])))
        write(joinpath(out,"summary.json"),CycleJSON.json(rows;pretty=true))
        println("CYCLE RESULT ",last(rows));flush(stdout)
    end
    for scenario in ("scenario_01_pmin0_qsym","scenario_02_pmin0_qsym")
        c,st,angles=global_scale_case(root,scenario);idx=DroopOPF._bus_indices(c.network)
        controls=VoltVarDroop[];attachments=GeneratorControlAttachment[]
        for (k,g) in enumerate(c.generators)
            g.available || continue
            slope=.04/(g.q_max-g.q_min);reference=st.vm[idx[g.bus_id]]+slope*st.qg[k]
            push!(controls,VoltVarDroop(VoltageSchedule(reference),slope,0.,
                ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max)))
            push!(attachments,GeneratorControlAttachment(g.id,length(controls),RegulatedLocation(:bus,g.bus_id)))
        end
        p=FeasibilityProblem(attach_controls(c,controls,attachments);angle_limits=angles)
        replay=check_feasibility(p;witnesses=[FeasibilityWitness(st)],solve_missing=false)
        replay.status==:feasible || error("source replay failed")
        started=time();d=DroopOPF._feasibility_lp(p;psd_clique_limit=8);build=time()-started
        # Check generated cycle cuts against the physical source W=V*V'.
        x=zeros(length(d.bounds));x[d.v]=st.vm;x[d.w]=st.vm.^2
        for (k,(i,j)) in enumerate(d.edges)
            product=st.vm[i]*st.vm[j]*cis(st.va[i]-st.va[j]);x[d.wr[k]]=real(product);x[d.wi[k]]=imag(product)
        end
        isempty(DroopOPF._flp_psd_cuts(d,x)) || error("PSD cuts excluded the source point")
        println("CYCLE SCALE START ",scenario," cliques=",length(d.cliques));flush(stdout)
        r=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit,max_rounds=30,psd_clique_limit=8)
        r.status==:certified_infeasible && error("certificate excluded a known feasible source point")
        write_feasibility_result(joinpath(out,scenario*"-lp.json"),p,r)
        write_feasibility_result(joinpath(out,scenario*"-source.json"),p,replay)
        a=only(r.attempts)
        push!(rows,Dict("case"=>scenario,"status"=>"source feasible; LP $(r.status)","build_seconds"=>build,
            "seconds"=>a["elapsed_seconds"],"variables"=>a["variables"],"rows"=>a["rows"],
            "cliques"=>a["psd_cliques"],"lifted_edges"=>a["lifted_edges"],"psd_cuts"=>a["psd_cuts"]))
        write(joinpath(out,"summary.json"),CycleJSON.json(rows;pretty=true))
        println("CYCLE SCALE RESULT ",last(rows));flush(stdout)
    end
    rows
end
if abspath(PROGRAM_FILE)==@__FILE__
    run_cycle_feasibility()
end
