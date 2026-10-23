# Staged, individually designed demand qualification. Import never optimizes.
include("s2_500bus_network_reduction.jl")
include("s2_500bus_separator_starts.jl")
const SDQ_OUT=joinpath(S2500_OUT,"solver_demand_qualification")
const SDQ_SOURCE=read(@__FILE__,String)
sdq_reduced(c;kwargs...)=nr_build_ac(c;power_balance_slacks=false,kwargs...)

function sdq_scaled_seed(study,seed,ratio)
    states=Dict{Symbol,Union{Nothing,ACState{Float64}}}()
    for (id,state) in seed.states
        if isnothing(state);states[id]=nothing;continue;end
        states[id]=ACState(copy(state.vm),copy(state.va),state.pg.*ratio,state.qg.*ratio)
    end
    SCOPFResult(states,Dict(id=>d*ratio for (id,d) in seed.balancing_power),seed.objective*ratio,
        :NOT_RUN,:NO_SOLUTION,study.mode,seed.encoding,1e-6,1e-6,1e-6,"scaled physical continuation start",
        study.reactive_assignments,seed.tap_settings,seed.shunt_settings,study.tap_controls,study.shunt_controls,study.control_policy)
end

function sdq_attempt(prefix,master,controls,seedstudy,seed,angles,solver,f,config)
    folder=joinpath(S2500_OUT,prefix)
    original_prefix=prefix;build_retry=0
    while ispath(folder)
        build_retry+=1;prefix=original_prefix*"-buildretry-$build_retry"
        folder=joinpath(S2500_OUT,prefix)
    end
    mkpath(folder)
    write(joinpath(folder,"loaded_driver.jl"),SDQ_SOURCE)
    write(joinpath(folder,"loaded_network_reduction.jl"),NR_SOURCE)
    for file in ("s2_500bus_solver_demand_qualification.jl","s2_arpae500_recovery.jl","s2_arpae500_qualification.jl","s2_500bus_network_reduction.jl","audit_s2_500bus_solver_demand.py")
        cp(joinpath(@__DIR__,file),joinpath(folder,"executed_"*file))
    end
    fd_save(joinpath(folder,"free-controls.json"),controls)
    lane=s2500_targeted_attempt(prefix,master,controls,seedstudy,Dict(f=>seed),angles;
        solver,retry=true,factors=(f,),objective_factor=f,normalization=false,
        droop_normalization=config.normalized,seconds_budget=config.seconds,
        ac_builder=config.reduced ? sdq_reduced : DroopOPF._build_acopf_model,
        mpcc_implied_q_bounds=hasproperty(config,:implied_q) && config.implied_q,
        linear_solver=hasproperty(config,:umfpack) && config.umfpack ? MadNLP.UmfpackSolver : nothing,
        optimizer_options=hasproperty(config,:options) ? config.options : Dict{String,Any}(),
        ccopt_sigma_init=hasproperty(config,:sigma_init) ? config.sigma_init : 1e-6,
        cc_builder=hasproperty(config,:scaled_mpcc) && config.scaled_mpcc ? sdq_scaled_mpcc : DroopOPF._build_complementarity_opf_model,
        mu=config.mu,scheduled=config.scheduled)
    script=joinpath(@__DIR__,"audit_s2_500bus_solver_demand.py")
    python=get(ENV,"SDQ_PYTHON","/tmp/s214-plot-env/bin/python")
    read(`$python $script $folder`,String)
    audit=JSON.parsefile(joinpath(folder,"independent-audit.json"))
    accepted=lane.record["accepted"] && audit["accepted"]
    (;lane...,accepted)
end

function sdq_run(solver=:ipopt;factor=1.,max_rounds=3,separator_solver=solver,recovery=false,
    seed_override=nothing,seed_factor=1.,label_suffix="",configs_override=nothing)
    confirmation=get(ENV,"SDQ_CONTROL_CONFIRMATION","")
    isempty(strip(confirmation)) && error("Campaign equipment confirmation required")
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    label="$(solver)-$(round(Int,factor*10000))"*(recovery ? "-recovery" : "")*label_suffix
    summaryfile=joinpath(SDQ_OUT,"summary-$label.json")
    isfile(summaryfile) && error("Preserve completed campaign: $summaryfile")
    nominal=JSON.parsefile(joinpath(S2500_QUAL,"summary-expanded-madnlp-reserve.json"))
    directory=joinpath(S2500_OUT,nominal["selected"])
    # Prefer the freshly qualified Ipopt controller when starting CCOpt.
    previous=joinpath(SDQ_OUT,"summary-ipopt-$(round(Int,factor*10000)).json")
    reuse_same_demand=false
    if solver!=:ipopt && isfile(previous)
        p=JSON.parsefile(previous)
        if p["accepted"]
            directory=joinpath(S2500_OUT,p["selected"]);reuse_same_demand=true
        end
    end
    seedstudy=read_study(joinpath(directory,reuse_same_demand ? "controller.json" : "optimized-1.0.json"))
    seed=read_scopf_result(joinpath(directory,"result-$(reuse_same_demand ? factor : 1.).json"))
    factor==1. || reuse_same_demand || (seed=s2500_demand_seed(seedstudy,seed,factor))
    if !isnothing(seed_override)
        directory=joinpath(S2500_OUT,seed_override)
        seedstudy=read_study(joinpath(directory,"controller.json"))
        seed=read_scopf_result(joinpath(directory,"result-$seed_factor.json"))
        seed_factor==factor || (seed=sdq_scaled_seed(seedstudy,seed,factor/seed_factor))
    end
    events=eligible_contingencies(contingency_catalog(seedstudy.case))
    @assert length(events)==389
    controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    @assert length(controls)==51 && length(seedstudy.tap_controls)==131 && length(seedstudy.shunt_controls)==11
    working=Set(c.id for c in seedstudy.contingencies)
    configs=solver==:ccopt ? [(;reduced=false,normalized=true,seconds=300.,mu=1e-6,scheduled=true),
        (;reduced=false,normalized=false,seconds=300.,mu=1e-10,scheduled=false),
        (;reduced=false,normalized=true,seconds=300.,mu=1e-8,scheduled=true)] :
        [(;reduced=true,normalized=true,seconds=300.,mu=1e-6,scheduled=true),
        (;reduced=false,normalized=true,seconds=300.,mu=1e-6,scheduled=true),
        (;reduced=false,normalized=false,seconds=300.,mu=1e-6,scheduled=true)]
    if recovery
        solver==:ccopt || error("Recovery configuration is specific to CCOpt")
        configs=[(;reduced=false,normalized=true,seconds=300.,mu=1e-6,scheduled=true,implied_q=true,umfpack=true),
            (;reduced=false,normalized=true,seconds=300.,mu=1e-8,scheduled=false,implied_q=true,umfpack=true)]
    elseif solver==:madnlp
        configs=[merge(c,(;umfpack=true)) for c in configs]
    end
    isnothing(configs_override) || (configs=configs_override)
    mkpath(SDQ_OUT)
    fd_save(joinpath(SDQ_OUT,"protocol-$label.json"),(;confirmation,solver,separator_solver,factor,max_rounds,configs,
        seed=relpath(directory,S2500_OUT),tap_controls=seedstudy.tap_controls,shunt_controls=seedstudy.shunt_controls,
        seed_native_status=seed.termination_status,seed_is_initialization_only=true,
        control_policy=seedstudy.control_policy,free_slopes=51,free_references=51,
        security_scope="389 connected outages; islanding cases separate",policy="normal limits, no relief, exact active response",
        objective="active base losses at this individual demand",source_sha256=bytes2hex(sha256(SDQ_SOURCE))))
    rounds=Any[];accepted=false;selected=nothing
    for round in 1:max_rounds
        master=DroopOPF._copy_study(seedstudy;contingencies=filter(c->c.id in working,events))
        anchorstudy=seedstudy;anchorseed=seed
        attempts=Any[];chosen=nothing
        for (i,config) in enumerate(configs)
            # Compare full and reduced starts against the accepted anchor;
            # the third configuration may use the second run's last iterate.
            if i==2;seedstudy=anchorstudy;seed=anchorseed;end
            prefix="solver_demand_qualification/$label/round-$round/attempt-$i"
            lane=sdq_attempt(prefix,master,controls,seedstudy,seed,angles,solver,factor,config)
            push!(attempts,(;name=lane.record["name"],accepted=lane.accepted,record=lane.record))
            fd_save(joinpath(SDQ_OUT,"progress-$label.json"),(;round,attempts,working_outages=sort(collect(working);by=string)))
            if lane.accepted
                chosen=lane;break
            end
            # Invalid iterates may seed retries, but never qualify the controller.
            if haskey(lane.results,factor) && !isnothing(lane.results[factor].states[:base])
                seed=lane.results[factor];seedstudy=lane.study
            end
        end
        scan=nothing
        if !isnothing(chosen)
            seedstudy=chosen.study;seed=chosen.results[factor]
            full=DroopOPF._copy_study(seedstudy;case=DroopOPF._feasibility_scaled_case(seedstudy.case,factor),contingencies=events)
            scanprefix="solver_demand_qualification/$label/round-$round/demand-$factor"
            scan=s2500_scan(scanprefix,full,seed,angles;solver=separator_solver,max_failures=4)
            accepted=scan.accepted
            selected=chosen.record["name"]
        end
        push!(rounds,(;round,attempts,selected,scan=isnothing(scan) ? nothing :
            (;accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed),
            working_outages=sort(collect(working);by=string)))
        fd_save(summaryfile,(;solver,factor,accepted,selected,rounds,full_n1_accepted=false))
        accepted && break
        isnothing(scan) && break
        old=length(working);union!(working,scan.failed)
        length(working)>old || break
        enriched=sdq_separator_starts(seedstudy,seed,joinpath(S2500_OUT,selected),factor)
        seedstudy=enriched.controller;seed=enriched.seed
    end
    println("SDQ COMPLETE ",label," accepted=",accepted);flush(stdout)
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    solver=Symbol(get(ARGS,1,"ipopt"));factor=parse(Float64,get(ARGS,2,"1.0"))
    sdq_run(solver;factor)
end
