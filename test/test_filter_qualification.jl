include(joinpath(@__DIR__,"..","examples","scopf_filter_qualification.jl"))

@testset "Frozen filter enhancement and held-out network qualification" begin
    discovery = qualification_inputs(:discovery)
    heldout = qualification_inputs(:heldout)
    @test length(discovery) == length(heldout) == 12
    @test isempty(intersect(Set(x.case.id for x in discovery),Set(x.case.id for x in heldout)))
    case = discovery[2].case
    base = qualification_base(case)
    @test equilibrium_report(case,base).valid
    legacy = validate_contingency_filter(case,base.state;reactive_guard=0.0,
        ac_risk_guard=false,optimizer_attributes=Dict("max_iter"=>400))
    @test sum(r.screened_unresolved for r in legacy.families) == 2
    enhanced = filter_contingencies(case,base.state)
    @test all(d.action == :exact for d in enhanced)
    @test any(d.reason == :reactive_reserve_guard for d in enhanced)
    @test_throws ArgumentError filter_contingencies(case,base.state;reactive_guard=-0.1)
    for input in heldout
        base = qualification_base(input.case)
        @test equilibrium_report(input.case,base).valid
        baseline = filter_contingencies(input.case,base.state;reactive_guard=0.0,ac_risk_guard=false)
        guarded = filter_contingencies(input.case,base.state)
        # Enhancements only escalate; they must never screen a previously exact route.
        @test all(a.action != :screened || b.action == :screened for (a,b) in zip(guarded,baseline))
        @test all(d.action == :exact for d in guarded if d.device_kind == :generator)
    end
    phases = Dict{Symbol,Float64}()
    timed = assess_contingency_pipeline(discovery[1].case,
        qualification_base(discovery[1].case).state;_phase_timings=phases)
    @test timed.checks.routing_complete
    @test all(haskey(phases,k) && phases[k] >= 0 for k in
        (:filter,:prepare_build,:optimize_extract,:validate_rank))
end

@testset "Reactive-flow loading and voltage-redistribution guards" begin
    source = scopf_parallel_case()
    for mode in (:apparent,:voltage)
        buses = [Bus(b.id;reference=b.reference,
            v_min=mode == :voltage ? 0.95 : 0.9,
            v_max=mode == :voltage ? 1.05 : 1.1) for b in source.network.buses]
        network = ACNetwork(buses,[Branch(b.id,b.from_bus,b.to_bus;
            resistance=b.resistance,reactance=b.reactance,
            thermal_limit=mode == :apparent ? 0.25 : 2.0,kind=b.kind)
            for b in source.network.branches])
        case = Case("risk-$mode";base_power=100.0,base_frequency=50.0,network,
            loads=[Load(1,2;p=mode == :apparent ? 0.02 : 0.3,
                q=mode == :apparent ? 0.3 : 0.1)],generators=source.generators,
            controls=source.controls,attachments=source.attachments)
        base = scopf_validation_base(case)
        @test equilibrium_report(case,base).valid
        old = filter_contingencies(case,base.state;reactive_guard=0.0,ac_risk_guard=false)
        @test count(d -> d.action == :screened,old) == 2
        new = filter_contingencies(case,base.state)
        reason = mode == :apparent ? :predicted_apparent_risk : :voltage_redistribution_guard
        @test all(d.reason == reason for d in new if d.device_kind != :generator)
    end
end
