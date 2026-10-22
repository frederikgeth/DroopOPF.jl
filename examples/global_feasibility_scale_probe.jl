# Read-only source-data probe and optional LP certificate runs; no SCOPF.
using DroopOPF,HiGHS
const ScaleJSON=DroopOPF.JSON
function global_scale_case(root,scenario)
    dir=joinpath(root,"test","data","arpae","c1_network01","results",scenario)
    n=ScaleJSON.parsefile(joinpath(dir,"network_model.json"))
    sol=ScaleJSON.parsefile(joinpath(dir,"opf_ac.json"))["solution"]
    ordered(d)=sort!(collect(d);by=x->parse(Int,first(x)))
    buses=[Bus(parse(Int,k);v_min=b["vmin"],v_max=b["vmax"],reference=b["bus_type"]==3) for (k,b) in ordered(n["bus"]) if b["bus_type"]!=4]
    ids=Set(b.id for b in buses);branches=Branch[]
    for (k,b) in ordered(n["branch"])
        b["f_bus"] in ids && b["t_bus"] in ids || continue
        abs(b["g_fr"])+abs(b["g_to"])+abs(b["b_fr"]-b["b_to"])<1e-12 || error("asymmetric branch model is unsupported")
        push!(branches,Branch(parse(Int,k),b["f_bus"],b["t_bus"];resistance=b["br_r"],reactance=b["br_x"],
            charging=b["b_fr"]+b["b_to"],thermal_limit=b["rate_a"],available=b["br_status"]==1,
            tap_ratio=b["tap"],phase_shift=b["shift"],kind=b["transformer"] ? :transformer : :line))
    end
    generators=[Generator(parse(Int,k),g["gen_bus"];available=g["gen_status"]==1,
        p_min=g["pmin"],p_max=g["pmax"],q_min=g["qmin"],q_max=g["qmax"],
        initial_p=clamp(g["pg"],g["pmin"],g["pmax"]),initial_q=clamp(g["qg"],g["qmin"],g["qmax"]))
        for (k,g) in ordered(n["gen"]) if g["gen_bus"] in ids]
    loads=[Load(parse(Int,k),l["load_bus"];p=l["pd"],q=l["qd"]) for (k,l) in ordered(n["load"]) if l["status"]==1 && l["load_bus"] in ids]
    # This probe is explicitly fixed equipment: dispatchable banks are represented
    # by their supplied admittance, without inferring any control freedom.
    shunts=[FixedShunt(parse(Int,k),s["shunt_bus"];conductance=s["gs"],susceptance=s["bs"],available=s["status"]==1)
        for (k,s) in ordered(n["shunt"]) if s["shunt_bus"] in ids]
    c=Case(scenario;base_power=n["baseMVA"],base_frequency=60.,network=ACNetwork(buses,branches;shunts),
        generators,loads,controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    st=ACState([Float64(sol["bus"][string(b.id)]["vm"]) for b in buses],[Float64(sol["bus"][string(b.id)]["va"]) for b in buses],
        [Float64(get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"]) for g in generators],
        [Float64(get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"]) for g in generators])
    angles=Dict(b.id=>(n["branch"][string(b.id)]["angmin"],n["branch"][string(b.id)]["angmax"]) for b in branches)
    c,st,angles
end

function run_global_scale_probe()
    root=normpath(joinpath(@__DIR__,".."));out=joinpath(root,"artifacts","s1_global_scale_probe");mkpath(out)
    rows=[]
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
        candidate=attach_controls(c,controls,attachments);p=FeasibilityProblem(candidate;angle_limits=angles)
        witness=FeasibilityWitness(st;label="saved source OPF / calibrated no-deadband droops")
        replay=check_feasibility(p;witnesses=[witness],solve_missing=false)
        replay.status==:feasible || error("source calibration failed for $scenario")
        target=c.network.buses[argmax(st.vm)].id
        for mode in (:soc,:global)
            start=time();built=build_global_feasibility_model(p;target_bus=target,mode)
            elapsed=time()-start;audit=seed_global_feasibility!(built,st)
            audit.max_violation<1e-7 || error("scale probe replay failed: $audit")
            push!(rows,merge(Dict("case"=>scenario,"buses"=>length(c.network.buses),"generators"=>length(c.generators),
                "droops"=>length(controls),"build_seconds"=>elapsed,"seed_audit"=>DroopOPF._json_data(audit)),built.metadata))
        end
        write_feasibility_result(joinpath(out,scenario*"-calibration.json"),p,replay)
        # Test only the cheap, bounded certificate tier on the large case.
        lp=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit=30.,max_rounds=12)
        lp.status==:certified_infeasible && error("outer relaxation excluded a known feasible source point")
        write_feasibility_result(joinpath(out,scenario*"-lp.json"),p,lp)
        write(joinpath(out,"summary.json"),ScaleJSON.json(rows;pretty=true))
        println("SCALE PROBE ",scenario," ",length(c.network.buses)," buses; source witness passed; LP ",lp.status);flush(stdout)
    end
end
if abspath(PROGRAM_FILE)==@__FILE__
    run_global_scale_probe()
end
