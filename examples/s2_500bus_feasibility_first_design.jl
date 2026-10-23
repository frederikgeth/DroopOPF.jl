# Feasibility-first warm starts followed by the requested free-droop loss design.
include("s2_500bus_scaled_mpcc.jl")
function sdq_feasibility_design(solver=:ccopt;factor=1.,label_suffix="")
    @assert !isempty(strip(get(ENV,"SDQ_CONTROL_CONFIRMATION","")))
    @assert factor<1.1 # The original-policy 110% obstruction is certified.
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    label="$(solver)-$(round(Int,factor*10000))-feasibility-first"*label_suffix
    summary=joinpath(SDQ_OUT,"summary-$label.json");isfile(summary) && error("Preserve completed recovery")
    candidates=Any[]
    for file in readdir(SDQ_OUT;join=true)
        startswith(basename(file),"summary-") && endswith(file,".json") || continue
        p=JSON.parsefile(file);isnothing(p["selected"]) && continue
        audit=joinpath(S2500_OUT,p["selected"],"independent-audit.json")
        isfile(audit) && JSON.parsefile(audit)["accepted"] || continue
        push!(candidates,p)
    end
    @assert !isempty(candidates)
    prior=sort(candidates;by=p->(abs(p["factor"]-factor),p["accepted"] ? 0 : 1))[1]
    directory=joinpath(S2500_OUT,prior["selected"]);oldfactor=Float64(prior["factor"])
    controller=read_study(joinpath(directory,"controller.json"))
    previous=read_study(joinpath(directory,"optimized-$oldfactor.json"))
    controller=DroopOPF._copy_study(controller;contingencies=previous.contingencies)
    seed=read_scopf_result(joinpath(directory,"result-$oldfactor.json"))
    seed=sdq_scaled_seed(controller,seed,factor/oldfactor)
    separator_sources=String[];added_outages=Symbol[]
    if factor==oldfactor
        enriched=sdq_separator_starts(controller,seed,directory,factor)
        controller=enriched.controller;seed=enriched.seed;separator_sources=enriched.sources;added_outages=enriched.added
    end
    controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    events=eligible_contingencies(contingency_catalog(controller.case));working=Set(c.id for c in controller.contingencies)
    fd_save(joinpath(SDQ_OUT,"protocol-$label.json"),(;confirmation=ENV["SDQ_CONTROL_CONFIRMATION"],solver,factor,
        source=prior["selected"],source_factor=oldfactor,maximum_master_models=2,seconds_per_stage=180.,
        unresolved_separator_starts=separator_sources,added_outages,
        maximum_native_optimizer_calls=4,sharing="102 free droop variables shared across base and included outages, one demand per master",
        stages=["constant-objective feasibility, no artificial injections","base active-loss minimization"],policy="normal limits, no relief, exact response"))
    attempts=Any[];rounds=Any[];selected=nothing;accepted=false
    for i in 1:2
        prefix="solver_demand_qualification/$label/round-$i/attempt-1";folder=joinpath(S2500_OUT,prefix)
        ispath(folder) && error("Preserve existing attempt")
        mkpath(folder)
        for file in ("s2_500bus_feasibility_first_design.jl","s2_500bus_separator_starts.jl","s2_500bus_scaled_mpcc.jl","s2_500bus_solver_demand_qualification.jl","s2_500bus_network_reduction.jl","s2_arpae500_recovery.jl","audit_s2_500bus_solver_demand.py")
            cp(joinpath(@__DIR__,file),joinpath(folder,"executed_"*file))
        end
        fd_save(joinpath(folder,"free-controls.json"),controls)
        master=DroopOPF._copy_study(controller;contingencies=filter(c->c.id in working,events))
        reduced=solver!=:ccopt
        lane=s2500_targeted_attempt(prefix,master,controls,controller,Dict(factor=>seed),angles;
            solver,retry=true,factors=(factor,),objective_factor=factor,droop_normalization=true,normalization=false,
            seconds_budget=180.,feasibility_first=true,mu=1e-8,scheduled=true,
            optimizer_options=solver==:ipopt && i==2 ? Dict("hessian_approximation"=>"limited-memory") : Dict{String,Any}(),
            linear_solver=solver==:ipopt ? nothing : MadNLP.UmfpackSolver,
            mpcc_implied_q_bounds=solver==:ccopt,
            ac_builder=reduced ? sdq_reduced : DroopOPF._build_acopf_model,
            cc_builder=i==2 ? sdq_scaled_mpcc : DroopOPF._build_complementarity_opf_model)
        python=get(ENV,"SDQ_PYTHON","/tmp/s214-plot-env/bin/python");script=joinpath(@__DIR__,"audit_s2_500bus_solver_demand.py")
        read(`$python $script $folder`,String)
        good=lane.record["accepted"] && JSON.parsefile(joinpath(folder,"independent-audit.json"))["accepted"]
        attempt=(;name=prefix,accepted=good,record=lane.record);push!(attempts,attempt)
        scan=nothing
        if good
            selected=prefix;controller=lane.study;seed=lane.results[factor]
            full=DroopOPF._copy_study(controller;case=DroopOPF._feasibility_scaled_case(controller.case,factor),contingencies=events)
            scan=s2500_scan("solver_demand_qualification/$label/round-$i/demand-$factor",full,seed,angles;solver=:ipopt)
            accepted=scan.accepted
        end
        push!(rounds,(;round=i,attempts=[attempt],selected,working_outages=sort(collect(working);by=string),
            scan=isnothing(scan) ? nothing : (;accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed)))
        fd_save(summary,(;solver,factor,accepted,selected,rounds,full_n1_accepted=false))
        accepted && break
        isnothing(scan) || union!(working,scan.failed)
    end
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    sdq_feasibility_design(Symbol(get(ARGS,1,"ccopt"));factor=parse(Float64,get(ARGS,2,"1.0")))
end
