# Optional environment: DroopOPF + SCIP. No SCOPF optimization is launched.
using DroopOPF, SCIP, HiGHS
const GlobalJSON=DroopOPF.JSON

function run_arpae14_global_feasibility(;time_limit=60.)
    root=normpath(joinpath(@__DIR__,".."))
    out=joinpath(root,"artifacts","s1_arpae14_global_feasibility");mkpath(out)
    state(d)=ACState(Float64.(d["vm"]),Float64.(d["va"]),Float64.(d["pg"]),Float64.(d["qg"]))
    conditions=GlobalJSON.parsefile(joinpath(root,"artifacts","s1_arpae14_feasibility_gate","no_deadband-qualification.json"))["data"]["conditions"]
    source100=state(conditions["calibration/source"]["result"]["witness"]["state"])
    source90=state(conditions["source/0.9"]["result"]["witness"]["state"])
    angles=Dict(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in conditions["source/0.9"]["problem"]["angle_limits_rad"])
    base=read_study(joinpath(root,"artifacts","s1_arpae14_stress","source-study.json")).case
    phase=GlobalJSON.parsefile(joinpath(root,"artifacts","s1_arpae14_infeasibility_diagnostic","voltage_phase1.json"))
    audits=[];rows=[]
    # Verify the model maps known physical equilibria before using any solver bound.
    for (label,c,s) in (("source100",base,source100),("source90",DroopOPF._feasibility_scaled_case(base,.9),source90))
        p=FeasibilityProblem(c;angle_limits=angles)
        for mode in (:soc,:global)
            built=build_global_feasibility_model(p;target_bus=8,mode)
            audit=seed_global_feasibility!(built,s)
            audit.max_violation<1e-7 || error("global formulation failed $label/$mode replay: $audit")
            push!(audits,Dict("name"=>label,"mode"=>string(mode),"audit"=>DroopOPF._json_data(audit)))
        end
    end
    for variant in ("no_deadband","with_deadband")
        c=read_study(joinpath(root,"artifacts","s1_arpae14_corrected_comparison","verified",variant*"-study.json")).case
        p100=FeasibilityProblem(c;angle_limits=angles)
        p=FeasibilityProblem(DroopOPF._feasibility_scaled_case(c,.9);angle_limits=angles)
        lp=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit=30.,max_rounds=30)
        write_feasibility_result(joinpath(out,"$variant-verified-lp.json"),p,lp)
        push!(rows,merge(Dict("variant"=>variant,"mode"=>"verified_lp","gate_status"=>string(lp.status)),only(lp.attempts)))
        relaxed=state(first(x for x in phase if x["variant"]==variant)["state"])
        for mode in (:soc,:global)
            for (label,problem,s) in (("calibrated100",p100,source100),("voltage_relaxed90",p,relaxed))
                built=build_global_feasibility_model(problem;target_bus=8,mode)
                audit=seed_global_feasibility!(built,s)
                audit.max_violation<1e-7 || error("global formulation failed $variant/$label/$mode replay: $audit")
                push!(audits,Dict("name"=>"$variant/$label","mode"=>string(mode),"audit"=>DroopOPF._json_data(audit)))
            end
            println("GLOBAL EXPERIMENT ",variant," ",mode);flush(stdout)
            result=solve_global_feasibility(p;target_bus=8,mode,optimizer_factory=SCIP.Optimizer,
                initial_state=relaxed,time_limit,silent=false,
                optimizer_attributes=Dict("numerics/feastol"=>1e-9,"limits/gap"=>1e-4,"limits/nodes"=>100000))
            write_feasibility_result(joinpath(out,"$variant-$mode.json"),p,result.result)
            push!(rows,merge(Dict("variant"=>variant,"gate_status"=>string(result.result.status)),result.ledger))
            write(joinpath(out,"summary.json"),GlobalJSON.json(rows;pretty=true))
            write(joinpath(out,"model_audits.json"),GlobalJSON.json(audits;pretty=true))
            println("GLOBAL RESULT ",variant," ",mode," ",result.ledger["termination_status"],
                " bound=",result.ledger["objective_bound_pu"]," objective=",result.ledger["objective_value_pu"]);flush(stdout)
        end
    end
    rows
end

if abspath(PROGRAM_FILE)==@__FILE__
    run_arpae14_global_feasibility()
end
