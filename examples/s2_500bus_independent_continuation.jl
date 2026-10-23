# Bounded single-demand recovery. Each master has independent free curves.
include("s2_500bus_solver_demand_qualification.jl")
function sdq_independent_continuation()
    @assert !isempty(strip(get(ENV,"SDQ_CONTROL_CONFIRMATION","")))
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    phase=JSON.parsefile(joinpath(SDQ_OUT,"summary-ipopt-10000.json"));@assert phase["accepted"]
    root=joinpath(S2500_OUT,phase["selected"])
    original=read_study(joinpath(root,"optimized-1.0.json"))
    nominal=read_scopf_result(joinpath(root,"result-1.0.json"))
    angles=fd_inputs(500).angles;controls=s214_multi_controls(fd_inputs(500).base)
    events=eligible_contingencies(contingency_catalog(original.case))
    fd_save(joinpath(SDQ_OUT,"protocol-independent-continuation.json"),(;confirmation=ENV["SDQ_CONTROL_CONFIRMATION"],
        solver=:ipopt,paths=[(.975,.95,.925,.9),(1.025,1.05)],seconds_per_attempt=180.,maximum_attempts_per_master=2,
        maximum_outage_addition_rounds=2,policy="normal limits, no relief, exact response",
        sharing="All 102 droop parameters shared across outages, independently optimized at each demand. Intermediate points are not exhaustively qualified unless explicitly scanned."))
    allrows=Any[]
    for path in ((.975,.95,.925,.9),(1.025,1.05))
        study=original;seed=nominal;previous=1.;working=Set(c.id for c in original.contingencies)
        for f in path
            label="ipopt-$(round(Int,f*10000))-continuation";summary=joinpath(SDQ_OUT,"summary-$label.json")
            isfile(summary) && error("Preserve completed continuation: $summary")
            scaled=sdq_scaled_seed(study,seed,f/previous);rounds=Any[];accepted=false;selected=nothing;chosen=nothing
            for round in 1:2
                master=DroopOPF._copy_study(study;contingencies=filter(e->e.id in working,events))
                attempts=Any[];chosen=nothing
                for (i,reduced) in enumerate((true,false))
                    config=(;reduced,normalized=true,seconds=180.,mu=1e-6,scheduled=true)
                    name="solver_demand_qualification/$label/round-$round/attempt-$i"
                    lane=sdq_attempt(name,master,controls,study,scaled,angles,:ipopt,f,config)
                    push!(attempts,(;name=lane.record["name"],accepted=lane.accepted,record=lane.record))
                    fd_save(joinpath(SDQ_OUT,"progress-$label.json"),(;round,attempts))
                    if lane.accepted;chosen=lane;break;end
                end
                scan=nothing
                if !isnothing(chosen)
                    selected=chosen.record["name"];study=chosen.study;seed=chosen.results[f]
                    if f in (.9,.95,1.05)
                        full=DroopOPF._copy_study(study;case=DroopOPF._feasibility_scaled_case(study.case,f),contingencies=events)
                        scan=s2500_scan("solver_demand_qualification/$label/round-$round/demand-$f",full,seed,angles;solver=:ipopt)
                        accepted=scan.accepted
                    end
                end
                push!(rounds,(;round,attempts,selected,working_outages=sort(collect(working);by=string),
                    scan=isnothing(scan) ? nothing : (;accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed)))
                fd_save(summary,(;solver=:ipopt,factor=f,accepted,selected,rounds,intermediate=!(f in (.9,.95,1.05)),
                    master_accepted=!isnothing(chosen),full_n1_accepted=false))
                isnothing(chosen) && break
                isnothing(scan) && break
                accepted && break
                old=length(working);union!(working,scan.failed);length(working)>old || break
                scaled=seed
            end
            push!(allrows,(;factor=f,master_accepted=!isnothing(chosen),qualified=accepted,selected))
            fd_save(joinpath(SDQ_OUT,"independent-continuation-progress.json"),(;points=allrows))
            isnothing(chosen) && break
            # A partial scan does not qualify this point but can still be an
            # explicitly identified numerical start for the next master.
            previous=f
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && sdq_independent_continuation()
