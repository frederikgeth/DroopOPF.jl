# Run explicitly: julia --project=. examples/p3_multi_period.jl /fresh/output
using DroopOPF, JSON, SHA
include("m7_2_case.jl")
const P3_ROOT=normpath(joinpath(@__DIR__,".."))
p3_data(x)=DroopOPF._json_data(x)
p3_save(p,x)=(mkpath(dirname(p));write(p,JSON.json(p3_data(x);pretty=true)*"\n"))
p3_state(s)=ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]))
function p3_inputs(n)
    if n==3
        c=m72_case();factors=[.9,1.1,.95,1.,.9]
        return (;c,factors,states=[m5_initial_state(c) for f in factors],angles=Dict(),sources=String[])
    end
    paths=n==14 ? ["artifacts/s1_arpae14_joint_reference/relative5-study.json",
        "artifacts/s1_arpae14_closeout/calibration_reference.json",
        "artifacts/s1_arpae14_closeout/demand_witnesses.json",
        "artifacts/s1_arpae14_closeout/angle_limits.json"] : [
        "artifacts/s1_arpae500/calibrated-study.json","artifacts/s1_arpae500/selected_reference.json",
        "artifacts/s1_arpae500/demand_witnesses.json","artifacts/s1_free_droop/500/angle_limits.json"]
    paths=joinpath.(P3_ROOT,paths)
    c=read_study(paths[1]).case;ref=JSON.parsefile(paths[2]);w=JSON.parsefile(paths[3])
    c=with_tap_settings(c,Dict(parse(Int,k)=>Float64(v) for (k,v) in ref["taps"]))
    c=with_shunt_settings(c,Dict(parse(Int,k)=>Float64(v) for (k,v) in ref["susceptances"]))
    factors=n==14 ? [.9,1.,1.1,1.,.9] : [.9,1.,1.05,1.,.9]
    states=n==14 ? [p3_state(only(r for r in w if r["tags"]["factor"]==f)["state"]) for f in factors] :
        [p3_state(w["fixed-$f"]["state"]) for f in factors]
    angles=Dict(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in JSON.parsefile(paths[4]))
    (;c,factors,states,angles,sources=paths)
end
function p3_result_data(r)
    (;periods=p3_data(r.periods),droops=p3_data(r.droops),
        droop_controls=[(;control_id=c.control_id,bounds=c.bounds,initial=p3_data(c.initial)) for c in r.droop_controls],
        objective_mwh=r.objective_mwh,termination_status=r.termination_status,primal_status=r.primal_status)
end
function p3_attempt(study,controls,states,folder;seconds=120.)
    mkpath(folder)
    for (t,c) in enumerate(study.cases);write_study(joinpath(folder,"period-$t.json"),Study(c));end
    p3_save(joinpath(folder,"contract.json"),(;duration_hours=study.duration_hours,
        ramp_limits=study.ramp_limits,angle_limits=study.angle_limits,
        droop_controls=[(;control_id=c.control_id,bounds=c.bounds) for c in controls],
        initial_states=states,objective="duration-weighted active energy loss MWh",
        equipment="fixed supplied reference taps and bank settings; zero movement",
        seconds,contingencies=false))
    println("START ",folder);flush(stdout)
    timed=@timed optimize_multi_period(study;droop_controls=controls,initial_states=states,
        optimizer_attributes=Dict("tol"=>1e-8,"acceptable_tol"=>1e-7,"acceptable_iter"=>5,
            "max_cpu_time"=>seconds,"max_iter"=>2500,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive"))
    r=timed.value;a=validate_multi_period(study,r)
    p3_save(joinpath(folder,"result.json"),p3_result_data(r))
    p3_save(joinpath(folder,"audit.json"),a)
    summary=(;accepted=a.valid,termination_status=r.termination_status,objective_mwh=r.objective_mwh,
        wall_seconds=timed.time,allocated_bytes=timed.bytes)
    p3_save(joinpath(folder,"summary.json"),summary)
    println("END ",folder," ",summary);flush(stdout)
    (;result=r,audit=a,summary)
end
function p3_run(folder;sizes=(3,14,500))
    ispath(folder)&&error("Fresh output directory required")
    mkpath(folder)
    p3_save(joinpath(folder,"protocol.json"),(;scope="P3 deterministic multi-period AC shared reactive droop design",
        ordered_hours=5,ramps="25% of active capability range per hour; assumed sensitivity, not manufacturer data; no initial/terminal ramp",
        equipment="no selected movable controls; taps and continuous bank susceptances fixed at S1 supplied reference for every period",
        normal_limits=true,load_relief=false,security_qualified=false,
        objective="loss MWh, local optimality only",s2="paused and unchanged",p2="open and unchanged"))
    summaries=Any[]
    for n in sizes
        x=p3_inputs(n);c=x.c
        cases=[DroopOPF._feasibility_scaled_case(c,f) for f in x.factors]
        ramps=Dict(g.id=>(.25*(g.p_max-g.p_min),.25*(g.p_max-g.p_min)) for g in c.generators if g.available)
        n==3 && (ramps[7]=(0.,0.))
        study=MultiPeriodStudy(cases;duration_hours=ones(5),ramp_limits=ramps,angle_limits=x.angles)
        bounds=n==3 ? [DroopControl(i;slope_bounds=(.5d.slope,2d.slope),v_ref_bounds=(d.schedule.v_ref-.02,d.schedule.v_ref+.02)) for (i,d) in enumerate(c.controls)] :
            [DroopControl(i;slope_bounds=(.02/(d.capability.q_max-d.capability.q_min),.08/(d.capability.q_max-d.capability.q_min)),v_ref_bounds=(d.schedule.v_ref-.02,d.schedule.v_ref+.02)) for (i,d) in enumerate(c.controls)]
        dir=joinpath(folder,string(n));mkpath(dir)
        p3_save(joinpath(dir,"inputs.json"),(;factors=x.factors,
            sources=Dict(relpath(p,P3_ROOT)=>bytes2hex(sha256(read(p))) for p in x.sources),
            fixed_taps=Dict(b.id=>b.tap_ratio for b in c.network.branches),
            fixed_banks=Dict(b.id=>(;conductance=real(bank_admittance(b)),susceptance=imag(bank_admittance(b))) for b in c.network.banks)))
        fixed=p3_attempt(study,DroopControl[],x.states,joinpath(dir,"fixed");seconds=n==500 ? 180. : 40.)
        starts=fixed.summary.accepted ? [r.state for r in fixed.result.periods] : x.states
        design=p3_attempt(study,bounds,starts,joinpath(dir,"design");seconds=n==500 ? 240. : 60.)
        push!(summaries,(;buses=n,factors=x.factors,fixed=fixed.summary,design=design.summary,
            improvement_percent=fixed.summary.accepted && design.summary.accepted ?
                100*(fixed.result.objective_mwh-design.result.objective_mwh)/fixed.result.objective_mwh : nothing))
        p3_save(joinpath(folder,"summary.json"),summaries)
    end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("Supply fresh output directory")
    p3_run(abspath(ARGS[1]))
end
