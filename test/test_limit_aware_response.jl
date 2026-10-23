using JSON
import MadNLP

@testset "Limit-aware automatic active response" begin
    net = ACNetwork([Bus(1; reference=true)], Branch{Float64}[])
    case = Case("limit-aware-response"; base_power=100.0, base_frequency=50.0,
        network=net, loads=[Load(1,1;p=0.9,q=0.0)],
        generators=[
            Generator(1,1;p_min=0.0,p_max=0.25,q_min=-1.0,q_max=1.0,initial_p=0.2),
            Generator(2,1;p_min=0.0,p_max=1.5,q_min=-1.0,q_max=1.0,initial_p=0.3),
            Generator(3,1;p_min=0.0,p_max=0.5,q_min=-1.0,q_max=1.0,initial_p=0.4),
            Generator(4,1;p_min=0.0,p_max=0.0,q_min=-1.0,q_max=1.0,initial_p=0.0)],
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
    outage = Contingency(:trip;generator_ids=[3])
    base = ACState([1.0],[0.0],[0.2,0.3,0.4,0.0],zeros(4))
    study = Study(case; contingencies=[outage], participation=Dict(1=>1.,2=>1.,3=>1.,4=>1.))
    @test default_participation(case) == Dict(1=>0.25,2=>1.5,3=>0.5)
    @test Study(case).participation == default_participation(case)
    @test_throws ArgumentError Study(case;contingencies=[outage],participation=Dict(4=>1.))
    scenario = scenario_case(case,outage)
    @test DroopOPF._participation(study,scenario) == [0.5,0.5,0.,0.]
    # One participant saturates; the other supplies the remainder. A positive
    # weight on the zero-range unit must not prevent that response.
    result = evaluate_contingencies(study,base)
    @test equilibrium_report(study,result).valid
    @test result.states[:trip].pg ≈ [0.25,0.65,0.,0.] atol=1e-6
    @test result.balancing_power[:trip] ≈ 0.7 atol=1e-6
    # The signal is not the delivered aggregate response (0.4 pu).
    @test sum(result.states[:trip].pg[1:2]-base.pg[1:2]) ≈ 0.4 atol=1e-6
    corrupted = deepcopy(result)
    corrupted.states[:trip].pg[1] -= 0.02
    corrupted.states[:trip].pg[2] += 0.02 # Preserve AC balance, break response law.
    report = equilibrium_report(study,corrupted)
    @test :active_power_response in report.violations[:trip]
    limited = Study(case;contingencies=[outage],participation=Dict(1=>1.,2=>1.),
        redispatch_limits=Dict(1=>0.02,2=>0.5))
    limited_result = evaluate_contingencies(limited,base)
    @test equilibrium_report(limited,limited_result).valid
    @test limited_result.states[:trip].pg ≈ [0.22,0.68,0.,0.] atol=1e-6
    # Negative response has its own saturation: g1 stops at its lower bound.
    signal = DroopOPF._response_signal_start(study,scenario,base.pg,-0.45)
    @test signal ≈ -0.5 atol=1e-10
    @test clamp(base.pg[1]+0.5signal,0.,0.25) ≈ 0.
    @test clamp(base.pg[2]+0.5signal,0.,1.5) ≈ 0.05 atol=1e-10
    nonparticipant = Study(case;contingencies=[outage],participation=Dict(2=>1.))
    nr = evaluate_contingencies(nonparticipant,base)
    @test equilibrium_report(nonparticipant,nr).valid
    @test nr.states[:trip].pg ≈ [0.2,0.7,0.,0.] atol=1e-6
    # Full downward response after losing a consuming unit.
    down_gens = [case.generators[1],case.generators[2],
        Generator(3,1;p_min=-0.5,p_max=0.0,q_min=-1.0,q_max=1.0,initial_p=-0.45),
        case.generators[4]]
    down_case = Case("downward-response";base_power=100.0,base_frequency=50.0,
        network=net,loads=[Load(1,1;p=0.05,q=0.0)],generators=down_gens,
        controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    down_base = ACState([1.0],[0.0],[0.2,0.3,-0.45,0.0],zeros(4))
    down_study = Study(down_case;contingencies=[outage],participation=Dict(1=>1.,2=>1.))
    down_result = evaluate_contingencies(down_study,down_base)
    @test equilibrium_report(down_study,down_result).valid
    @test down_result.states[:trip].pg ≈ [0.,0.05,0.,0.] atol=1e-6
    # Both reactive encodings implement the same bounded active law.
    for candidate in (study,limited)
        exact = evaluate_contingencies(candidate,base;encoding=:complementarity)
        @test equilibrium_report(candidate,exact;coupling_tolerance=1e-5).valid
    end
    # A different smooth backend must enforce the same active saturation.
    mad = evaluate_contingencies(study,base;optimizer_factory=MadNLP.Optimizer)
    @test equilibrium_report(study,mad).valid
    # Controller active capability is included in fallback weights.
    droop = VoltVarDroop(VoltageSchedule(1.0),0.05,0.0,
        ReactiveCapability(p_min=0.1,p_max=0.2,q_min=-1.,q_max=1.))
    assignment = ReactiveControlAssignment(1,droop,RegulatedLocation(:bus,1))
    @test default_participation(case;reactive_assignments=[assignment])[1] ≈ 0.1
    cap_case = Case("controller-active-bound";base_power=100.0,base_frequency=50.0,
        network=net,loads=case.loads,generators=case.generators,controls=[droop],
        attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
    cap_study = Study(cap_case;contingencies=[outage],participation=Dict(1=>1.,2=>1.))
    cap_result = evaluate_contingencies(cap_study,base)
    @test equilibrium_report(cap_study,cap_result).valid
    @test cap_result.states[:trip].pg ≈ [0.2,0.7,0.,0.] atol=1e-6
    insufficient = Study(case;contingencies=[outage],participation=Dict(1=>1.,2=>1.),
        redispatch_limits=Dict(1=>0.02,2=>0.1))
    rejected = evaluate_contingencies(insufficient,base;
        optimizer_attributes=Dict("max_iter"=>100))
    @test !equilibrium_report(insufficient,rejected).valid
    mktempdir() do dir
        path = write_study(joinpath(dir,"study.json"),study)
        @test read_study(path).participation == study.participation
        d = JSON.parsefile(path)
        delete!(d,"active_response")
        d["schema_version"] = 9
        write(path,JSON.json(d))
        @test_throws ArgumentError read_study(path)
        rp = write_scopf_result(joinpath(dir,"result.json"),result)
        @test equilibrium_report(study,read_scopf_result(rp)).valid
        d = JSON.parsefile(rp)
        delete!(d,"active_response")
        d["schema_version"] = 4
        write(rp,JSON.json(d))
        @test_throws ArgumentError read_scopf_result(rp)
    end
end
