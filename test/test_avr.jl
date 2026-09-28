using Ipopt
using MadNLP

@testset "Exact AVR regimes and independent validation" begin
    assignments = [ReactiveControlAssignment(1, AVR(1.0), RegulatedLocation(:bus, 1))]
    for (q, voltage) in ((0.0, 1.0), (0.5, 0.98), (-0.5, 1.02))
        case = Case("avr-regime"; base_power=100.0, base_frequency=50.0,
            controls=VoltVarDroop[], attachments=GeneratorControlAttachment[],
            network=ACNetwork([Bus(1; reference=true)], Branch{Float64}[]),
            generators=[Generator(1, 1; p_min=0.0, p_max=2.0,
                q_min=-0.5, q_max=0.5, initial_p=0.5, initial_q=q)],
            loads=[Load(1, 1; p=0.5, q=q)])
        witness = ACState([voltage], [0.0], [0.5], [q])
        @test validate_equilibrium(case, witness; reactive_assignments=assignments).valid
        invalid_voltage = q == 0 ? 0.98 : 2.0 - voltage
        invalid = ACState([invalid_voltage], [0.0], [0.5], [q])
        @test :avr in validate_equilibrium(case, invalid;
            reactive_assignments=assignments).violations
        result = solve_opf_complementarity(case; reactive_assignments=assignments,
            initial_state=witness)
        @test result.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL)
        @test validate_equilibrium(case, result; reactive_assignments=assignments).valid
        @test result.complementarity_residual_max < 1e-6
        @test result.state.qg[1] ≈ q atol=1e-6
        if q == 0
            @test result.state.vm[1] ≈ 1.0 atol=1e-5
        elseif q > 0
            @test result.state.vm[1] <= 1.0 + 1e-5
        else
            @test result.state.vm[1] >= 1.0 - 1e-5
        end
        @test_throws ArgumentError validate_equilibrium(case, witness;
            reactive_assignments=assignments, avr_voltage_tolerance=-1.0)
    end
end

@testset "Remote and branch-terminal AVR locations" begin
    network = ACNetwork([Bus(1; reference=true), Bus(2)],
        [Branch(1, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=5.0),
         Branch(2, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=5.0)])
    generator = Generator(1, 1; p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0,
        initial_p=0.5, initial_q=0.2)
    case = Case("remote-avr"; base_power=100.0, base_frequency=50.0, network,
        generators=[generator], loads=[Load(1, 2; p=0.5, q=0.2)],
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
    remote = [ReactiveControlAssignment(1, AVR(1.0), RegulatedLocation(:remote_bus, 2))]
    seed = ACState([1.01, 1.0], [0.0, -0.05], [0.5], [0.2])
    for solvefn in (
        () -> solve_opf_complementarity(case; reactive_assignments=remote, initial_state=seed),
        () -> solve_opf(case; reactive_assignments=remote, initial_state=seed, smooth_epsilon=1e-4),
    )
        result = solvefn()
        @test result.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL)
        @test validate_equilibrium(case, result; reactive_assignments=remote,
            power_tolerance=1e-5).valid
        @test result.state.vm[2] ≈ 1.0 atol=1e-5
    end
    @test_throws ArgumentError validate_reactive_assignments(case,
        [ReactiveControlAssignment(1, AVR(1.0), RegulatedLocation(:generator_terminal, 2))])

    terminal = RegulatedLocation(:branch_terminal, 2; side=:to, branch_id=1)
    terminal_assignment = [ReactiveControlAssignment(1, AVR(1.0), terminal)]
    @test validate_reactive_assignments(case, terminal_assignment)
    @test isempty(DroopOPF._active_avr_groups(
        scenario_case(case, Contingency(:line_1; branch_ids=[1])), terminal_assignment))
end

@testset "Common-bus AVR capability sharing" begin
    network = ACNetwork([Bus(1; reference=true)], Branch{Float64}[])
    generators = [
        Generator(1, 1; p_min=0.0, p_max=1.0, q_min=-0.2, q_max=0.2,
            initial_p=0.25, initial_q=0.12),
        Generator(2, 1; p_min=0.0, p_max=1.0, q_min=-0.8, q_max=0.8,
            initial_p=0.25, initial_q=0.48),
    ]
    case = Case("avr-sharing"; base_power=100.0, base_frequency=50.0,
        network, generators, loads=[Load(1, 1; p=0.5, q=0.6)],
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
    assignments = [ReactiveControlAssignment(i, AVR(1.0), RegulatedLocation(:bus, 1))
        for i in 1:2]
    witness = ACState([1.0], [0.0], [0.25, 0.25], [0.12, 0.48])
    @test validate_equilibrium(case, witness; reactive_assignments=assignments).valid
    wrong_share = ACState([1.0], [0.0], [0.25, 0.25], [0.1, 0.5])
    @test :avr_sharing in validate_equilibrium(case, wrong_share;
        reactive_assignments=assignments).violations

    exact = solve_opf_complementarity(case; reactive_assignments=assignments,
        initial_state=witness)
    @test validate_equilibrium(case, exact; reactive_assignments=assignments).valid
    @test exact.state.qg ≈ witness.qg atol=1e-7
    for optimizer in (Ipopt.Optimizer, MadNLP.Optimizer)
        smooth = solve_opf(case; reactive_assignments=assignments,
            optimizer_factory=optimizer, initial_state=witness, smooth_epsilon=1e-4)
        @test validate_equilibrium(case, smooth; reactive_assignments=assignments).valid
        @test smooth.state.qg ≈ witness.qg atol=1e-7
    end

    conflicting = [assignments[1], ReactiveControlAssignment(2, AVR(1.01),
        RegulatedLocation(:bus, 1))]
    @test_throws ArgumentError validate_reactive_assignments(case, conflicting)
    outage = scenario_case(case, Contingency(:generator_1; generator_ids=[1]))
    surviving_group = only(DroopOPF._active_avr_groups(outage, assignments))
    @test only(surviving_group).generator_id == 2
end

@testset "Smooth and exact AVR two-bus Q-limit transitions" begin
    assignments = [ReactiveControlAssignment(1, AVR(1.0), RegulatedLocation(:bus, 1))]
    for demand in (-0.8, 0.0, 0.8)
        q = clamp(demand, -0.5, 0.5)
        # Lossless line, zero angles: Q12 = V1*(V1-1)/x.
        voltage = (1 + sqrt(1 + 0.4 * (q - demand))) / 2
        support_q = (1 - voltage) / 0.1
        case = Case("avr-transition"; base_power=100.0, base_frequency=50.0,
            controls=VoltVarDroop[], attachments=GeneratorControlAttachment[],
            network=ACNetwork([Bus(1; reference=true), Bus(2; v_min=1.0, v_max=1.0)],
                [Branch(1, 1, 2; resistance=0.0, reactance=0.1, thermal_limit=5.0)]),
            generators=[Generator(1, 1; p_min=-1.0, p_max=1.0,
                q_min=-0.5, q_max=0.5, initial_q=q),
                Generator(2, 2; p_min=-1.0, p_max=1.0,
                    q_min=-2.0, q_max=2.0, initial_q=support_q)],
            loads=[Load(1, 1; p=0.0, q=demand)])
        witness = ACState([voltage, 1.0], [0.0, 0.0], [0.0, 0.0], [q, support_q])
        @test validate_equilibrium(case, witness; reactive_assignments=assignments).valid
        result = solve_opf_complementarity(case; reactive_assignments=assignments,
            initial_state=witness)
        @test result.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL)
        @test validate_equilibrium(case, result; reactive_assignments=assignments).valid
        @test result.state.vm[1] ≈ voltage atol=1e-5
        @test result.state.qg[1] ≈ q atol=1e-5
        for optimizer in (Ipopt.Optimizer, MadNLP.Optimizer)
            smooth = solve_opf(case; reactive_assignments=assignments,
                initial_state=witness, optimizer_factory=optimizer,
                smooth_epsilon=1e-4)
            @test smooth.termination_status in
                (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL)
            @test validate_equilibrium(case, smooth; reactive_assignments=assignments,
                power_tolerance=1e-5).valid
            @test smooth.state.vm[1] ≈ result.state.vm[1] atol=1e-5
            @test smooth.state.qg[1] ≈ result.state.qg[1] atol=1e-5
        end
    end
end
