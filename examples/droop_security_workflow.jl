include("droop_security_cases.jl")
using JSON, SHA

security_json(path,x) = write(path,JSON.json(DroopOPF._json_data(x);pretty=true)*"\n")
function security_provenance()
    root = dirname(@__DIR__)
    files = sort(filter(p->endswith(p,".jl"),readdir(joinpath(root,"src");join=true)))
    (;julia=string(VERSION),source_sha256=bytes2hex(sha256(join(read.(files,String)))),
        project_sha256=bytes2hex(sha256(read(joinpath(root,"Project.toml")))),
        manifest_sha256=bytes2hex(sha256(read(joinpath(root,"Manifest.toml")))))
end

function security_design_bundle(directory,study,design;context="Shared droop design")
    mkpath(directory)
    write_study(joinpath(directory,"input.json"),study)
    write_droop_security(joinpath(directory,"design.json"),design)
    audit = validate_droop_design(study,design)
    security_json(joinpath(directory,"validation.json"),audit)
    if Set(keys(design.settings)) == Set(c.control_id for c in design.controls)
        optimized = with_droop_settings(study,design)
        write_scopf_evaluation_report(joinpath(directory,"evaluation.md"),optimized,design.result;context)
        # Reference overlays reuse the established M3 curve plot for each control.
        for control in design.controls
            all(!isnothing(state) for state in values(design.result.states)) || break
            id = control.control_id
            scalar = DroopDesignResult(id,design.reference_settings[id],design.settings[id],NaN,design.result)
            write_droop_design_comparison_plot(joinpath(directory,"curve-$id.svg"),study,scalar)
        end
    end
    audit
end

function security_round_bundle(directory,round)
    out = joinpath(directory,"round-$(round.iteration)")
    security_design_bundle(out,round.study,round.design;
        context="Contingency-addition round $(round.iteration); master training set only. See audit.json for independent outage evaluations.")
    security_json(joinpath(out,"audit.json"),round)
    println("round $(round.iteration): training=$(length(round.study.contingencies)), audit=$(round.exhaustive_audit), added=$(round.added_ids)")
    flush(stdout)
end

function droop_security_reference(output)
    mkpath(output)
    case = droop_security_case()
    catalog = contingency_catalog(case)
    full = Study(case;contingencies=eligible_contingencies(catalog),participation=default_participation(case))
    controls = [DroopControl(1;slope_bounds=(.04,.08)),DroopControl(2;slope_bounds=(.04,.1))]
    options = (;smooth_epsilon=1e-5,optimizer_attributes=Dict("max_iter"=>1000,"max_cpu_time"=>30.,"max_wall_time"=>30.))
    security_json(joinpath(output,"protocol.json"),(;provenance=security_provenance(),
        full,controls,options,filter=(;loading_threshold=.8,voltage_guard=.02,reactive_guard=.1,ac_risk_guard=true),
        contract="Frozen three-bus full eligible N-1 reference; shared slope design, fixed references and deadbands; no global optimum claim."))
    base = DroopOPF._copy_study(full;contingencies=Contingency[])
    cold = solve_scopf(base;options...)
    write_scopf_evaluation_report(joinpath(mkpath(joinpath(output,"cold-base")),"evaluation.md"),base,cold;
        context="Cold-start diagnostic retained separately from the declared warm-start protocol.")
    seed = solve_scopf(base;initial_states=Dict(:base=>droop_security_start(case)),options...)
    equilibrium_report(base,seed).valid || error("declared base seed failed validation")
    starts = Dict(id=>seed.states[:base] for id in [:base;[c.id for c in full.contingencies]])
    fixed_seconds = @elapsed fixed = solve_scopf(full;initial_states=starts,options...)
    write_scopf_evaluation_report(joinpath(mkpath(joinpath(output,"fixed")),"evaluation.md"),full,fixed)
    full_seconds = @elapsed enumerated = optimize_droop_parameters(full,controls;initial_states=fixed.states,options...)
    full_validation = security_design_bundle(joinpath(output,"full"),full,enumerated;
        context="Full-enumeration reference: all five N-1 outages are training constraints.")
    base = DroopOPF._copy_study(full;contingencies=Contingency[])
    iterative_seconds = @elapsed iterative = optimize_droop_security(base,controls;
        max_rounds=5,batch_size=1,solver_kwargs=options,initial_states=seed.states,
        on_iteration=r->security_round_bundle(output,r))
    write_droop_security(joinpath(output,"result.json"),iterative)
    write(joinpath(output,"iterations.md"),markdown_report(iterative))
    last_round = last(iterative.iterations)
    gap = last_round.design.result.objective-enumerated.result.objective
    metrics = (;fixed_seconds,full_seconds,iterative_seconds,full_valid=full_validation.valid,
        full_objective=enumerated.result.objective,fixed_objective=fixed.objective,
        iterative_objective=last_round.design.result.objective,objective_gap=gap,
        objective_agreement=abs(gap)<=1e-6,eligible_accepted=iterative.eligible_accepted,
        full_n1_accepted=iterative.full_n1_accepted,iterations=length(iterative.iterations),
        catalog_count=length(catalog.entries),provenance=security_provenance())
    security_json(joinpath(output,"metrics.json"),metrics)
    write(joinpath(output,"report.md"),"""
# Full-enumeration versus iterative droop-SCOPF

Two shared slope variables on a three-bus meshed network, with one constrained
transformer, two line outages and two generator outages. Voltage references,
deadbands, Q limits, demand and active response are identical in both methods.

- Full-enumeration physical/design acceptance: **$(metrics.full_valid)**.
- Iterative full N-1 acceptance: **$(metrics.full_n1_accepted)**.
- Objective agreement at absolute tolerance 1e-6: **$(metrics.objective_agreement)**.
- Full objective: $(metrics.full_objective); iterative: $(metrics.iterative_objective).
- Fixed-curve SCOPF objective: $(metrics.fixed_objective).
- Final independent audit: $(length(last_round.assessments)) AC evaluations; $(length(last_round.errors)) errors.
- Wall seconds: fixed $(fixed_seconds), full design $(full_seconds), iterative $(iterative_seconds).

Timings include first-use compilation and report/plot generation in callbacks;
they are not isolated solver performance comparisons. All iteration evidence is
retained, including screened decisions that were subsequently audited. The
objective is base schedule deviation, not an imported generation-cost function.

![Design and audit progression](progress.png)

[Iteration table](iterations.md) · [Full design validation](full/evaluation.md) · [Fixed reference](fixed/evaluation.md)

$(join(["- [Round $(r.iteration)](round-$(r.iteration)/evaluation.md)" for r in iterative.iterations],"\n"))

Success applies only to this declared steady-state catalog and tolerances; it
is not a global optimum or dynamic-security certificate.
""")
    metrics
end

abspath(PROGRAM_FILE)==abspath(@__FILE__) && droop_security_reference(abspath(ARGS[1]))
