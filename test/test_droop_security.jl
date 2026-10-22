include(joinpath(@__DIR__,"..","examples","droop_security_cases.jl"))

@testset "Shared SCOPF droop design and full N-1 audit" begin
    case = droop_security_case()
    catalog = contingency_catalog(case)
    full = Study(case;contingencies=eligible_contingencies(catalog),participation=Dict(7=>1.,9=>1.))
    base = Study(case;participation=full.participation)
    seed = solve_scopf(base;smooth_epsilon=1e-5,initial_states=Dict(:base=>droop_security_start(case)))
    @test equilibrium_report(base,seed).valid
    starts = Dict(id=>seed.states[:base] for id in [:base;[c.id for c in full.contingencies]])
    fixed = solve_scopf(full;smooth_epsilon=1e-5,initial_states=starts)
    @test equilibrium_report(full,fixed).valid
    locked = [DroopControl(i;slope_bounds=(c.slope,c.slope)) for (i,c) in enumerate(case.controls)]
    reproduced = optimize_droop_parameters(full,locked;initial_states=fixed.states)
    @test validate_droop_design(full,reproduced).valid
    @test reproduced.result.objective ≈ fixed.objective atol=1e-7
    controls = [DroopControl(1;slope_bounds=(.04,.08)),DroopControl(2;slope_bounds=(.04,.1))]
    enumerated = optimize_droop_parameters(full,controls;initial_states=fixed.states)
    @test validate_droop_design(full,enumerated).valid
    @test Set(keys(enumerated.settings)) == Set([1,2])
    base = Study(case;participation=full.participation)
    iterative = optimize_droop_security(base,controls;max_rounds=5,batch_size=1,initial_states=seed.states,
        solver_kwargs=(;optimizer_attributes=Dict("max_iter"=>500)))
    @test iterative.full_n1_accepted
    @test iterative.eligible_accepted
    @test length(iterative.iterations) >= 2
    @test any(!isempty(r.added_ids) for r in iterative.iterations)
    @test last(iterative.iterations).exhaustive_audit
    @test length(last(iterative.iterations).assessments) == length(catalog.entries)
    @test all(a.report.valid for a in last(iterative.iterations).assessments)
    @test last(iterative.iterations).design.result.objective ≈ enumerated.result.objective atol=1e-6
    @test case.controls[2].slope == .075
    # A round limit must not turn an unresolved exhaustive audit into success.
    limited = optimize_droop_security(base,controls;max_rounds=1,initial_states=seed.states,
        solver_kwargs=(;optimizer_attributes=Dict("max_iter"=>300)))
    @test !limited.eligible_accepted
    @test !limited.full_n1_accepted
    @test limited.status == :iteration_limit
    @test last(limited.iterations).exhaustive_audit
    # Catalog subsets have narrower coverage even when every supplied outage passes.
    subset = ContingencyCatalog(case.id,catalog.entries[1:1])
    partial = optimize_droop_security(base,locked;catalog=subset,initial_states=seed.states)
    @test partial.eligible_accepted
    @test !partial.full_n1_accepted
    @test_throws ArgumentError optimize_droop_security(base,controls;max_rounds=0)
    @test_throws ArgumentError optimize_droop_security(base,controls;evaluation_kwargs=(;smooth_epsilon=.1))
    @test_throws ArgumentError optimize_droop_parameters(base,[controls[1],controls[1]])
    bad = deepcopy(enumerated)
    bad.settings[1] = DroopSettings(.5,1.,.01,.01)
    @test !validate_droop_design(full,bad).valid
    missing = deepcopy(enumerated)
    delete!(missing.settings,1)
    @test !validate_droop_design(full,missing).valid
    mktempdir() do dir
        @test isfile(write_droop_security(joinpath(dir,"result.json"),iterative))
        @test occursin("Full network N-1 accepted: true",markdown_report(iterative))
    end
end

@testset "Droop reconstruction preserves equipment and response policies" begin
    source = droop_security_case(;rating=2.0)
    bank = ShuntBank(201,30;step_susceptances=(.02,),legal_states=((0,),(1,),(2,)),state=(1,))
    case = Case("droop-security-equipment";base_power=source.base_power,base_frequency=source.base_frequency,
        network=ACNetwork(source.network.buses,source.network.branches;banks=[bank]),
        generators=source.generators,loads=source.loads,controls=source.controls,attachments=source.attachments)
    policy = SCOPFControlPolicy(taps=:corrective,shunts=:corrective,
        tap_movement_limits=Dict(11=>.005),shunt_movement_limits=Dict(201=>.01))
    catalog = contingency_catalog(case)
    study = Study(case;contingencies=[catalog.entries[2].contingency],
        participation=Dict(7=>2.,9=>1.),tap_controls=[TapControl(11;lower=.99,upper=1.01)],
        shunt_controls=[ShuntControl(201;lower=0.,upper=.04)],control_policy=policy)
    seed = solve_scopf(study;smooth_epsilon=1e-5,initial_states=Dict(id=>droop_security_start(case) for id in [:base;[c.id for c in study.contingencies]]))
    @test equilibrium_report(study,seed).valid
    design = optimize_droop_parameters(study,2;slope_bounds=(.04,.1),reference_result=seed)
    replay = with_droop_settings(study,design)
    @test replay.control_policy == policy
    @test replay.tap_controls == study.tap_controls
    @test replay.shunt_controls == study.shunt_controls
    @test replay.participation == study.participation
    @test validate_droop_design(study,design).valid
    heldout = evaluate_held_out_contingencies(study,design,[catalog.entries[3].contingency])
    @test heldout.study.control_policy == policy
    @test heldout.report.valid
    @test heldout.result.tap_settings[:base] == design.result.tap_settings[:base]
    assignments = reactive_control_assignments(case)
    explicit = Study(case;reactive_assignments=assignments)
    @test_throws ArgumentError optimize_droop_parameters(explicit,[DroopControl(1)])
end

@testset "Opt-in sparse droop balances preserve physical results" begin
    buses=[Bus(i;reference=i==1) for i in 1:8]
    branches=[Branch(i,i,mod1(i+1,8);resistance=.01,reactance=.1,thermal_limit=2.) for i in 1:8]
    control=VoltVarDroop(VoltageSchedule(1.;v_db_low=.99,v_db_high=1.01),.05,0.,
        ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.))
    case=Case("sparse-droop-eight-bus";base_power=100.,base_frequency=50.,
        network=ACNetwork(buses,branches),loads=[Load(1,5;p=.2,q=.05)],
        generators=[Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,initial_p=.2)],
        controls=[control],attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
    study=Study(case)
    sizes=Int[]
    function capture(model)
        ev=DroopOPF.JuMP.NLPEvaluator(model)
        DroopOPF.MOI.initialize(ev,[:Jac])
        push!(sizes,length(DroopOPF.MOI.jacobian_structure(ev)))
    end
    # Start on the responsive part of the curve: the flat deadband start can
    # stall both formulations with unmet reactive demand on some solver builds.
    initial=ACState(fill(.987,8),zeros(8),[.21],[.06])
    dense=solve_scopf(study;smooth_epsilon=1e-5,
        initial_states=Dict(:base=>initial),_model_hook=capture)
    sparse=solve_scopf(study;smooth_epsilon=1e-5,sparse_balance=true,
        initial_states=dense.states,_model_hook=capture)
    @test sizes[2] < sizes[1]
    @test equilibrium_report(study,dense).valid
    @test equilibrium_report(study,sparse).valid
    @test sparse.objective ≈ dense.objective atol=1e-7
end

if !isdefined(@__MODULE__, :qualification_inputs)
    include(joinpath(@__DIR__,"..","examples","scopf_filter_qualification.jl"))
end
@testset "Exhaustive final audit catches a droop-specific false screen" begin
    source = qualification_inputs(:discovery)[7].case
    anchor = qualification_base(source)
    overlay = security_droop_overlay(source,anchor.state)
    # Put the schedule objective at the independently valid anchor so the master
    # retains the operating point which exposes this discovered filter failure.
    generators = [Generator(g.id,g.bus_id;p_min=g.p_min,p_max=g.p_max,
        q_min=g.q_min,q_max=g.q_max,initial_p=anchor.state.pg[i],
        initial_q=anchor.state.qg[i]) for (i,g) in enumerate(overlay.generators)]
    case = Case("droop-false-screen-regression";base_power=overlay.base_power,
        base_frequency=overlay.base_frequency,network=overlay.network,loads=overlay.loads,
        generators,controls=overlay.controls,attachments=overlay.attachments)
    study = Study(case;participation=Dict(g.id=>1. for g in generators))
    controls = [DroopControl(i) for i in eachindex(case.controls)]
    result = optimize_droop_security(study,controls;max_rounds=1,
        initial_states=Dict(:base=>anchor.state),solver_kwargs=(;smooth_epsilon=1e-5,
            optimizer_attributes=Dict("max_iter"=>500)))
    last_round = last(result.iterations)
    @test last_round.exhaustive_audit
    decisions = Dict(d.contingency_id=>d for d in last_round.decisions)
    @test any(!a.report.valid && decisions[a.contingency.id].action==:screened for a in last_round.assessments)
    @test !result.eligible_accepted
    @test !result.full_n1_accepted
end
