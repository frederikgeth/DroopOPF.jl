using MadNLP
using CCOpt
using MathOptComplements
using NLPModelsJuMP

function _solver_compatibility_case()
    network = ACNetwork(
        [Bus(1; reference = true), Bus(2)],
        [Branch(1, 1, 2; resistance = 0.01, reactance = 0.1, thermal_limit = 5.0)],
    )
    generator = Generator(
        1,
        1;
        p_min = 0.0,
        p_max = 2.0,
        q_min = -1.0,
        q_max = 1.0,
        initial_p = 0.5,
        initial_q = 0.0,
    )
    control = VoltVarDroop(
        VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
        0.05,
        0.0,
        ReactiveCapability(p_min = 0.0, p_max = 2.0, q_min = -1.0, q_max = 1.0),
    )
    return Case(
        "solver-compatibility";
        base_power = 100.0,
        base_frequency = 50.0,
        network = network,
        loads = [Load(1, 2; p = 0.5, q = 0.2)],
        generators = [generator],
        controls = [control],
        attachments = [GeneratorControlAttachment(1, 1, RegulatedLocation(:bus, 1))],
    )
end

@testset "solver compatibility" begin
    case = _solver_compatibility_case()
    results = Dict{Symbol,Any}(
        :ipopt => solve_opf(case; smooth_epsilon = 1.0e-3, silent = true),
        :madnlp => solve_opf(
            case;
            smooth_epsilon = 1.0e-3,
            optimizer_factory = MadNLP.Optimizer,
            silent = true,
        ),
        :ccopt => solve_opf_complementarity(case; silent = true),
    )

    for result in values(results)
        @test result.state !== nothing
        @test result.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED)
        residual = equilibrium_residual(case, result.state)
        @test maximum(abs, residual.power.vector) < 1.0e-5
        @test maximum(abs, residual.droop) < 5.0e-4
    end
    @test abs(results[:madnlp].objective - results[:ipopt].objective) < 1.0e-8
    @test abs(results[:ccopt].objective - results[:ipopt].objective) < 1.0e-4
    @test results[:ccopt].complementarity_residual_max < 1.0e-5
end
