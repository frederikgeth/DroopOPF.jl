#= S2 equipment-aware SCOPF public qualification.

Pinned contract:
- PGLib v23.07 IEEE-118/300 fixtures already vendored under test/data;
- source-recorded transformer branch 8 (118) or 1 (300);
- non-islanding line outage 1 (118) or 10 (300);
- low-impact online generator outage 39 (118) or 69 (300);
- three generator-terminal AVRs selected by the released M8 headroom rule;
- direct and fixed-equipment-staged paths retained separately.

Usage:
  julia --project=. examples/s2_scopf_qualification.jl 118 ipopt
  julia --project=. examples/s2_scopf_qualification.jl 300 ipopt OUT --stage fixed_seed

The stage form is intended for `s2_scopf_orchestrator.jl`: every invocation is
a fresh process and writes its result before returning.  This prevents a later
large-case factorization from losing an earlier completed stage.
=#
using DroopOPF
using JSON
using MadNLP
using JuMP

const S2_CONTRACT = Dict(
    118 => (tap=8, line=1, generator=39),
    300 => (tap=1, line=10, generator=69),
)

function s2_avr_assignments(case, state; count=3)
    indices = DroopOPF._bus_indices(case.network)
    ranked = [(generator=g, setpoint=state.vm[indices[g.bus_id]],
        headroom=min(state.qg[i]-g.q_min,g.q_max-state.qg[i])/(g.q_max-g.q_min))
        for (i,g) in enumerate(case.generators) if g.available && g.q_max>g.q_min &&
        case.network.buses[indices[g.bus_id]].v_min+1e-5 <= state.vm[indices[g.bus_id]] <=
        case.network.buses[indices[g.bus_id]].v_max-1e-5]
    sort!(ranked;by=x->-x.headroom)
    selected=eltype(ranked)[]; used=Set{Int}()
    for item in ranked
        item.generator.bus_id in used && continue
        push!(selected,item);push!(used,item.generator.bus_id)
        length(selected)==count && break
    end
    length(selected)==count || error("fewer than $count qualified AVR locations")
    assignments=[ReactiveControlAssignment(x.generator.id,AVR(x.setpoint),
        RegulatedLocation(:generator_terminal,x.generator.bus_id)) for x in selected]
    assignments,selected
end

function s2_solve(study, solver; initial_states=Dict())
    options=Dict("max_iter"=>1000,"max_cpu_time"=>60.0,"tol"=>1e-8)
    solver==:ipopt && return solve_scopf(study;smooth_epsilon=1e-4,
        initial_states,optimizer_attributes=options)
    solver==:madnlp && return solve_scopf(study;smooth_epsilon=1e-4,
        initial_states,optimizer_factory=MadNLP.Optimizer,optimizer_attributes=options)
    solver==:ccopt && return solve_scopf(study;encoding=:complementarity,
        initial_states,optimizer_attributes=options)
    error("solver must be ipopt, madnlp, or ccopt")
end

function s2_phase1_solve(study,solver;initial_states=Dict())
    options=Dict("max_iter"=>1000,"max_cpu_time"=>60.0,"tol"=>1e-8)
    captured=Ref{Any}(nothing)
    hook=model->(captured[]=model)
    result=solver==:ipopt ? solve_scopf(study;smooth_epsilon=1e-4,
        initial_states,optimizer_attributes=options,_phase1_power_balance=true,
        _model_hook=hook) : solver==:madnlp ? solve_scopf(study;smooth_epsilon=1e-4,
        initial_states,optimizer_factory=MadNLP.Optimizer,optimizer_attributes=options,
        _phase1_power_balance=true,_model_hook=hook) : solver==:ccopt ?
        solve_scopf(study;encoding=:complementarity,initial_states,
            optimizer_attributes=options,_phase1_power_balance=true,
            _model_hook=hook) : error("unknown solver")
    model=captured[]
    slacks=model.ext[:power_balance_slacks]
    values=has_values(model) ? JuMP.value.(slacks) : Float64[]
    result,Dict("total_slack"=>isempty(values) ? nothing : sum(values),
        "max_slack"=>isempty(values) ? nothing : maximum(values),
        "nonzero_count_1e8"=>count(>(1e-8),values),
        "diagnostic_only"=>true)
end

function s2_row(study,result;coupling_tolerance=1e-5)
    report=equilibrium_report(study,result;power_tolerance=1e-5,
        droop_tolerance=1e-4,limit_tolerance=1e-5,coupling_tolerance)
    Dict("termination_status"=>string(result.termination_status),
        "primal_status"=>string(result.primal_status),"valid"=>report.valid,
        "physical_valid"=>report.physical_valid,"objective"=>
            isfinite(result.objective) ? result.objective : nothing,
        "violations"=>Dict(string(k)=>string.(v) for (k,v) in report.violations)),report
end

function s2_setup(network::Int)
    haskey(S2_CONTRACT,network) || error("network must be 118 or 300")
    contract=S2_CONTRACT[network]
    source=joinpath(@__DIR__,"..","test","data","pglib","v23.07",
        "pglib_opf_case$(network)_ieee.m")
    case=load_matpower_case(source;base_frequency=60.0)
    options=Dict("max_iter"=>1000,"max_cpu_time"=>60.0,"tol"=>1e-8)
    free=solve_opf(case;smooth_epsilon=1e-4,optimizer_attributes=options)
    free_report=validate_equilibrium(case,free;power_tolerance=1e-5)
    free_report.valid || error("S2 FreeQ anchor did not validate")
    assignments,selected=s2_avr_assignments(case,free.state)
    contingencies=[Contingency(Symbol("line_$(contract.line)");branch_ids=[contract.line]),
        Contingency(Symbol("generator_$(contract.generator)");generator_ids=[contract.generator])]
    participation=Dict(g.id=>1.0 for g in case.generators if g.available)
    branch=only(filter(b->b.id==contract.tap,case.network.branches))
    taps=[TapControl(branch.id;lower=.99*branch.tap_ratio,upper=1.01*branch.tap_ratio,
        initial=branch.tap_ratio,nominal=branch.tap_ratio)]
    fixed_study=Study(case;contingencies,participation,reactive_assignments=assignments)
    equipment_study=Study(case;contingencies,participation,
        reactive_assignments=assignments,tap_controls=taps)
    (;contract,case,free,assignments,selected,contingencies,participation,branch,
        fixed_study,equipment_study,options)
end

function s2_write_result(out,prefix,study,result)
    row,report=s2_row(study,result)
    write_scopf_result(joinpath(out,"$(prefix)-result.json"),result)
    write_scopf_report(joinpath(out,"$(prefix)-report.json"),report)
    write(joinpath(out,"$(prefix)-status.json"),JSON.json(row;pretty=true)*"\n")
    row,report
end

function s2_stage_studies(setup, staged)
    base_tap=staged.tap_settings[:base][setup.branch.id]
    # Persisted solver points may sit a few ulps beyond a bound while remaining
    # inside the independent validation tolerance. Include that accepted base
    # value exactly; this changes neither the value nor the movement budget.
    lower=min(.99*setup.branch.tap_ratio,base_tap)
    upper=max(1.01*setup.branch.tap_ratio,base_tap)
    taps=[TapControl(setup.branch.id;lower,upper,initial=base_tap,
        nominal=setup.branch.tap_ratio)]
    immediate=Study(setup.case;contingencies=setup.contingencies,
        participation=setup.participation,reactive_assignments=setup.assignments,
        tap_controls=taps)
    settled=Study(setup.case;contingencies=setup.contingencies,
        participation=setup.participation,reactive_assignments=setup.assignments,
        tap_controls=taps,control_policy=SCOPFControlPolicy(taps=:corrective,
            tap_movement_limits=Dict(setup.branch.id=>0.005)))
    immediate,settled
end

"""Run exactly one resumable S2 stage in the current process."""
function run_s2_stage(network::Int,solver::Symbol,out,stage::Symbol)
    mkpath(out)
    setup=s2_setup(network)
    if stage == :direct
        result=s2_solve(setup.equipment_study,solver)
        write_study(joinpath(out,"study.json"),setup.equipment_study)
        return first(s2_write_result(out,"direct",setup.equipment_study,result))
    elseif stage == :fixed_seed
        result=s2_solve(setup.fixed_study,solver;
            initial_states=Dict(:base=>setup.free.state))
        return first(s2_write_result(out,"fixed",setup.fixed_study,result))
    elseif stage == :staged
        fixed=read_scopf_result(joinpath(out,"fixed-result.json"))
        equilibrium_report(setup.fixed_study,fixed;power_tolerance=1e-5,
            droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5).valid || error("fixed-seed prerequisite is invalid")
        result=s2_solve(setup.equipment_study,solver;initial_states=fixed.states)
        return first(s2_write_result(out,"staged",setup.equipment_study,result))
    elseif stage in (:immediate,:settled,:assessment)
        staged=read_scopf_result(joinpath(out,"staged-result.json"))
        equilibrium_report(setup.equipment_study,staged;power_tolerance=1e-5,
            droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5).valid || error("staged prerequisite is invalid")
        immediate,settled=s2_stage_studies(setup,staged)
        if stage == :assessment
            immediate_result=read_scopf_result(joinpath(out,"immediate-result.json"))
            settled_result=read_scopf_result(joinpath(out,"settled-result.json"))
            assessment=assemble_scopf_response_stages(immediate,settled,
                immediate_result,settled_result;validation_kwargs=(;
                    power_tolerance=1e-5,droop_tolerance=1e-4,
                    limit_tolerance=1e-5,coupling_tolerance=1e-5))
            write_scopf_stage_assessment(joinpath(out,"stages.json"),assessment)
            write(joinpath(out,"stages.md"),markdown_report(assessment)*"\n")
            return Dict("immediate_valid"=>assessment.immediate_report.valid,
                "settled_valid"=>assessment.settled_report.valid)
        end
        study=stage == :immediate ? immediate : settled
        kwargs=solver==:ipopt ? (;smooth_epsilon=1e-4,
            optimizer_attributes=setup.options) : solver==:madnlp ?
            (;smooth_epsilon=1e-4,optimizer_factory=MadNLP.Optimizer,
                optimizer_attributes=setup.options) :
            (;encoding=:complementarity,optimizer_attributes=setup.options)
        result=solve_scopf(study;fixed_base_state=staged.states[:base],
            fixed_base_tap_settings=staged.tap_settings[:base],
            fixed_base_shunt_settings=get(staged.shunt_settings,:base,Dict{Int,Float64}()),
            initial_states=staged.states,kwargs...)
        return first(s2_write_result(out,string(stage),study,result))
    elseif stage == :fixed_direct_seed
        direct=read_scopf_result(joinpath(out,"direct-result.json"))
        direct_report=equilibrium_report(setup.equipment_study,direct;power_tolerance=1e-5,
            droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5)
        # A solver-status-rejected but independently physical direct point remains
        # a legitimate initialization witness. Its status is retained separately.
        direct_report.physical_valid || error("direct witness prerequisite is physically invalid")
        result=s2_solve(setup.fixed_study,solver;initial_states=direct.states)
        return first(s2_write_result(out,"fixed-direct-seed",setup.fixed_study,result))
    elseif stage == :staged_direct_seed
        fixed=read_scopf_result(joinpath(out,"fixed-direct-seed-result.json"))
        equilibrium_report(setup.fixed_study,fixed;power_tolerance=1e-5,
            droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5).valid || error("direct-witness fixed seed is invalid")
        result=s2_solve(setup.equipment_study,solver;initial_states=fixed.states)
        return first(s2_write_result(out,"staged-direct-seed",setup.equipment_study,result))
    elseif stage == :fixed_line_homotopy
        direct=read_scopf_result(joinpath(out,"direct-result.json"))
        direct_report=equilibrium_report(setup.equipment_study,direct;
            power_tolerance=1e-5,droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5)
        direct_report.physical_valid || error("direct witness prerequisite is physically invalid")
        line_study=Study(setup.case;contingencies=[first(setup.contingencies)],
            participation=setup.participation,reactive_assignments=setup.assignments)
        ids=(:base,first(setup.contingencies).id)
        initial=Dict(id=>direct.states[id] for id in ids)
        result=s2_solve(line_study,solver;initial_states=initial)
        write_study(joinpath(out,"fixed-line-homotopy-study.json"),line_study)
        return first(s2_write_result(out,"fixed-line-homotopy",line_study,result))
    elseif stage == :fixed_full_homotopy
        line_study=Study(setup.case;contingencies=[first(setup.contingencies)],
            participation=setup.participation,reactive_assignments=setup.assignments)
        line=read_scopf_result(joinpath(out,"fixed-line-homotopy-result.json"))
        line_report=equilibrium_report(line_study,line;power_tolerance=1e-5,
            droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5)
        line_report.physical_valid || error("line-homotopy prerequisite is physically invalid")
        direct=read_scopf_result(joinpath(out,"direct-result.json"))
        initial=copy(line.states)
        generator_id=last(setup.contingencies).id
        initial[generator_id]=direct.states[generator_id]
        result=s2_solve(setup.fixed_study,solver;initial_states=initial)
        return first(s2_write_result(out,"fixed-full-homotopy",setup.fixed_study,result))
    elseif stage == :staged_homotopy
        fixed=read_scopf_result(joinpath(out,"fixed-full-homotopy-result.json"))
        fixed_report=equilibrium_report(setup.fixed_study,fixed;power_tolerance=1e-5,
            droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5)
        fixed_report.physical_valid || error("full fixed homotopy is physically invalid")
        result=s2_solve(setup.equipment_study,solver;initial_states=fixed.states)
        return first(s2_write_result(out,"staged-homotopy",setup.equipment_study,result))
    elseif stage == :fixed_generator_homotopy
        direct=read_scopf_result(joinpath(out,"direct-result.json"))
        direct_report=equilibrium_report(setup.equipment_study,direct;
            power_tolerance=1e-5,droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5)
        direct_report.physical_valid || error("direct witness prerequisite is physically invalid")
        generator_study=Study(setup.case;contingencies=[last(setup.contingencies)],
            participation=setup.participation,reactive_assignments=setup.assignments)
        ids=(:base,last(setup.contingencies).id)
        initial=Dict(id=>direct.states[id] for id in ids)
        result=s2_solve(generator_study,solver;initial_states=initial)
        write_study(joinpath(out,"fixed-generator-homotopy-study.json"),generator_study)
        return first(s2_write_result(out,"fixed-generator-homotopy",generator_study,result))
    elseif stage == :fixed_full_generator_first
        generator_study=Study(setup.case;contingencies=[last(setup.contingencies)],
            participation=setup.participation,reactive_assignments=setup.assignments)
        generator=read_scopf_result(joinpath(out,"fixed-generator-homotopy-result.json"))
        generator_report=equilibrium_report(generator_study,generator;
            power_tolerance=1e-5,droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5)
        generator_report.physical_valid || error("generator-homotopy prerequisite is physically invalid")
        direct=read_scopf_result(joinpath(out,"direct-result.json"))
        initial=copy(generator.states)
        line_id=first(setup.contingencies).id
        initial[line_id]=direct.states[line_id]
        result=s2_solve(setup.fixed_study,solver;initial_states=initial)
        return first(s2_write_result(out,"fixed-full-generator-first",setup.fixed_study,result))
    elseif stage == :staged_generator_first
        fixed=read_scopf_result(joinpath(out,"fixed-full-generator-first-result.json"))
        fixed_report=equilibrium_report(setup.fixed_study,fixed;power_tolerance=1e-5,
            droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5)
        fixed_report.physical_valid || error("generator-first full fixed result is physically invalid")
        result=s2_solve(setup.equipment_study,solver;initial_states=fixed.states)
        return first(s2_write_result(out,"staged-generator-first",setup.equipment_study,result))
    elseif stage in (:direct_immediate,:direct_settled,:direct_assessment)
        direct=read_scopf_result(joinpath(out,"direct-result.json"))
        direct_report=equilibrium_report(setup.equipment_study,direct;
            power_tolerance=1e-5,droop_tolerance=1e-4,limit_tolerance=1e-5,
            coupling_tolerance=1e-5)
        direct_report.physical_valid || error("direct M9.1 anchor is physically invalid")
        immediate,settled=s2_stage_studies(setup,direct)
        if stage == :direct_assessment
            immediate_result=read_scopf_result(joinpath(out,"direct-immediate-result.json"))
            settled_result=read_scopf_result(joinpath(out,"direct-settled-result.json"))
            assessment=assemble_scopf_response_stages(immediate,settled,
                immediate_result,settled_result;validation_kwargs=(;
                    power_tolerance=1e-5,droop_tolerance=1e-4,
                    limit_tolerance=1e-5,coupling_tolerance=1e-5))
            write_scopf_stage_assessment(joinpath(out,"direct-stages.json"),assessment)
            write(joinpath(out,"direct-stages.md"),markdown_report(assessment)*"\n")
            return Dict("immediate_valid"=>assessment.immediate_report.valid,
                "settled_valid"=>assessment.settled_report.valid)
        end
        study=stage == :direct_immediate ? immediate : settled
        kwargs=solver==:ipopt ? (;smooth_epsilon=1e-4,
            optimizer_attributes=setup.options) : solver==:madnlp ?
            (;smooth_epsilon=1e-4,optimizer_factory=MadNLP.Optimizer,
                optimizer_attributes=setup.options) :
            (;encoding=:complementarity,optimizer_attributes=setup.options)
        result=solve_scopf(study;fixed_base_state=direct.states[:base],
            fixed_base_tap_settings=direct.tap_settings[:base],
            fixed_base_shunt_settings=get(direct.shunt_settings,:base,Dict{Int,Float64}()),
            initial_states=direct.states,kwargs...)
        prefix=stage == :direct_immediate ? "direct-immediate" : "direct-settled"
        return first(s2_write_result(out,prefix,study,result))
    elseif stage == :phase1_fixed
        direct=read_scopf_result(joinpath(out,"direct-result.json"))
        result,slacks=s2_phase1_solve(setup.fixed_study,solver;
            initial_states=direct.states)
        row,report=s2_write_result(out,"phase1-fixed",setup.fixed_study,result)
        payload=Dict("solver"=>string(solver),"result"=>row,"slacks"=>slacks,
            "classification"=>isnothing(slacks["max_slack"]) ? "no_point" :
                slacks["max_slack"]<=1e-7 ? "near_zero_balance_slack" :
                "positive_balance_slack",
            "acceptance_warning"=>"Phase-I is diagnostic and never counts as an accepted SCOPF result.")
        write(joinpath(out,"phase1-fixed.json"),JSON.json(payload;pretty=true)*"\n")
        return payload
    elseif stage == :phase1_strict
        phase1=read_scopf_result(joinpath(out,"phase1-fixed-result.json"))
        all(!isnothing(state) for state in values(phase1.states)) ||
            error("Phase-I did not produce every scenario state")
        result=s2_solve(setup.fixed_study,solver;initial_states=phase1.states)
        return first(s2_write_result(out,"phase1-strict",setup.fixed_study,result))
    else
        error("unknown stage: $stage")
    end
end

function run_s2(network::Int,solver::Symbol,out)
    mkpath(out)
    setup=s2_setup(network)
    (;contract,case,free,assignments,selected,contingencies,participation,branch,
        fixed_study,equipment_study,options)=setup

    direct=s2_solve(equipment_study,solver)
    direct_row,direct_report=s2_row(equipment_study,direct)
    write_study(joinpath(out,"study.json"),equipment_study)
    write_scopf_result(joinpath(out,"direct-result.json"),direct)
    write_scopf_report(joinpath(out,"direct-report.json"),direct_report)
    progress=Dict{String,Any}("network"=>network,"solver"=>string(solver),
        "completed_stages"=>["direct"],"direct"=>direct_row,
        "s1_scorecard_unchanged"=>true)
    write(joinpath(out,"progress.json"),JSON.json(progress;pretty=true)*"\n")
    fixed=s2_solve(fixed_study,solver;initial_states=Dict(:base=>free.state))
    fixed_row,fixed_report=s2_row(fixed_study,fixed)
    write_scopf_result(joinpath(out,"fixed-result.json"),fixed)
    write_scopf_report(joinpath(out,"fixed-report.json"),fixed_report)
    push!(progress["completed_stages"],"fixed_seed");progress["fixed_seed"]=fixed_row
    write(joinpath(out,"progress.json"),JSON.json(progress;pretty=true)*"\n")
    staged=nothing;staged_row=Dict("valid"=>false,"note"=>"fixed seed invalid")
    staged_report=nothing
    if fixed_report.valid
        staged=s2_solve(equipment_study,solver;initial_states=fixed.states)
        staged_row,staged_report=s2_row(equipment_study,staged)
        write_scopf_result(joinpath(out,"staged-result.json"),staged)
        write_scopf_report(joinpath(out,"staged-report.json"),staged_report)
        push!(progress["completed_stages"],"staged");progress["staged"]=staged_row
        write(joinpath(out,"progress.json"),JSON.json(progress;pretty=true)*"\n")
    end

    stages=nothing
    if !isnothing(staged_report) && staged_report.valid
        base_tap=staged.tap_settings[:base][branch.id]
        stage_taps=[TapControl(branch.id;lower=.99*branch.tap_ratio,
            upper=1.01*branch.tap_ratio,initial=base_tap,nominal=branch.tap_ratio)]
        immediate=Study(case;contingencies,participation,
            reactive_assignments=assignments,tap_controls=stage_taps)
        settled=Study(case;contingencies,participation,
            reactive_assignments=assignments,tap_controls=stage_taps,
            control_policy=SCOPFControlPolicy(taps=:corrective,
                tap_movement_limits=Dict(branch.id=>0.005)))
        kwargs=solver==:ipopt ? (;smooth_epsilon=1e-4,initial_states=staged.states,
            optimizer_attributes=options) : solver==:madnlp ?
            (;smooth_epsilon=1e-4,initial_states=staged.states,
                optimizer_factory=MadNLP.Optimizer,optimizer_attributes=options) :
            (;encoding=:complementarity,initial_states=staged.states,
                optimizer_attributes=options)
        stages=assess_scopf_response_stages(immediate,settled,staged;
            immediate_solve_kwargs=kwargs,
            validation_kwargs=(;power_tolerance=1e-5,droop_tolerance=1e-4,
                limit_tolerance=1e-5,coupling_tolerance=1e-5))
        write_scopf_stage_assessment(joinpath(out,"stages.json"),stages)
        write(joinpath(out,"stages.md"),markdown_report(stages)*"\n")
        push!(progress["completed_stages"],"response_stages")
        progress["response_stages"]=Dict("immediate_valid"=>stages.immediate_report.valid,
            "settled_valid"=>stages.settled_report.valid)
        write(joinpath(out,"progress.json"),JSON.json(progress;pretty=true)*"\n")
    end

    summary=Dict("kind"=>"DroopOPF.S2Qualification","network"=>network,
        "solver"=>string(solver),"contract"=>Dict("tap_branch_id"=>contract.tap,
            "line_outage_id"=>contract.line,"generator_outage_id"=>contract.generator,
            "tap_relative_bounds"=>[.99,1.01],"tap_movement_budget"=>.005,
            "max_iterations_per_solve"=>1000,"max_cpu_seconds_per_solve"=>60.0),
        "avr_selection"=>[Dict("generator_id"=>x.generator.id,
            "bus_id"=>x.generator.bus_id,"setpoint"=>x.setpoint,
            "normalized_q_headroom"=>x.headroom) for x in selected],
        "direct"=>direct_row,"fixed_seed"=>fixed_row,"staged"=>staged_row,
        "stages"=>isnothing(stages) ? nothing : Dict(
            "immediate_valid"=>stages.immediate_report.valid,
            "settled_valid"=>stages.settled_report.valid),
        "s1_scorecard_unchanged"=>true)
    write(joinpath(out,"summary.json"),JSON.json(summary;pretty=true)*"\n")
    summary
end

if abspath(PROGRAM_FILE) == @__FILE__
    network=isempty(ARGS) ? 118 : parse(Int,ARGS[1])
    solver=length(ARGS)<2 ? :ipopt : Symbol(ARGS[2])
    out=length(ARGS)<3 ? joinpath(@__DIR__,"..","artifacts","s2_scopf",
        "ieee$(network)-$(solver)") : abspath(ARGS[3])
    stage_index=findfirst(==("--stage"),ARGS)
    output=isnothing(stage_index) ? run_s2(network,solver,out) :
        run_s2_stage(network,solver,out,Symbol(ARGS[stage_index+1]))
    println(JSON.json(output;pretty=true))
end
