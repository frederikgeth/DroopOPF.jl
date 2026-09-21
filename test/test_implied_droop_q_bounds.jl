using Test, JuMP, Ipopt, MadNLP

isdefined(@__MODULE__, :m72_case) ||
    include(joinpath(@__DIR__, "..", "examples", "m7_2_case.jl"))

struct ImpliedDroopBuilt <: Exception end

function implied_droop_model(case, policies, mode; formulation = :explicit)
    captured = Ref{Any}(nothing)
    function hook(phase, model)
        if phase == :built
            captured[] = model
            throw(ImpliedDroopBuilt())
        end
    end
    try
        optimize_joint_design(
            case;
            policies...,
            initial_state = m5_initial_state(case),
            droop_q_bounds = mode,
            droop_q_formulation = formulation,
            _measurement_hook = hook,
        )
    catch err
        err isa ImpliedDroopBuilt || rethrow()
    end
    return captured[]
end

@testset "Reduced droop Q eliminates one variable and equality per attachment" begin
    case = m72_case()
    policies = (
        tap_controls = [TapControl(11; lower = 0.95, upper = 1.05)],
        shunt_controls = [ShuntControl(201)],
        droop_controls = [DroopControl(2; slope_bounds = (0.04, 0.1))],
    )
    explicit = implied_droop_model(case, policies, :explicit)
    reduced = implied_droop_model(case, policies, :explicit; formulation = :reduced)
    available_attachments = count(
        attachment -> only(g for g in case.generators if g.id == attachment.generator_id).available,
        case.attachments,
    )
    @test num_variables(explicit) - num_variables(reduced) == available_attachments
    @test num_nonlinear_constraints(explicit) - num_nonlinear_constraints(reduced) ==
          available_attachments
    @test reduced.ext[:droop_q_formulation] == :reduced
    @test Set(reduced.ext[:reduced_droop_q_generator_ids]) ==
          Set(a.generator_id for a in case.attachments)
    generator_indices = Dict(g.id => i for (i, g) in enumerate(case.generators))
    variable_names = Set(name.(all_variables(reduced)))
    @test all(
        "qg[$(generator_indices[a.generator_id])]" ∉ variable_names
        for a in case.attachments
    )
    @test_throws ArgumentError optimize_joint_design(
        case;
        droop_q_formulation = :reduced,
        droop_q_bounds = :implied,
    )
    @test_throws ArgumentError optimize_joint_design(case; droop_q_formulation = :bad)
end

@testset "Droop response implies attached generator Q bounds" begin
    case = m72_case()
    policies = (
        tap_controls = [TapControl(11; lower = 0.95, upper = 1.05)],
        shunt_controls = [ShuntControl(201)],
        droop_controls = [DroopControl(2; slope_bounds = (0.04, 0.1))],
    )
    explicit = implied_droop_model(case, policies, :explicit)
    implied = implied_droop_model(case, policies, :implied)
    @test name.(all_variables(explicit)) == name.(all_variables(implied))
    @test string.(all_nonlinear_constraints(explicit)) ==
          string.(all_nonlinear_constraints(implied))
    @test string(objective_function(explicit)) == string(objective_function(implied))
    @test explicit.ext[:droop_q_bounds] == :explicit
    @test isempty(explicit.ext[:implied_droop_q_bound_generator_ids])
    @test implied.ext[:droop_q_bounds] == :implied
    @test Set(implied.ext[:implied_droop_q_bound_generator_ids]) ==
          Set(a.generator_id for a in case.attachments)

    generator_indices = Dict(g.id => i for (i, g) in enumerate(case.generators))
    for attachment in case.attachments
        i = generator_indices[attachment.generator_id]
        explicit_q = only(v for v in all_variables(explicit) if name(v) == "qg[$i]")
        implied_q = only(v for v in all_variables(implied) if name(v) == "qg[$i]")
        @test has_lower_bound(explicit_q) && has_upper_bound(explicit_q)
        @test !has_lower_bound(implied_q) && !has_upper_bound(implied_q)
    end

    excursions = Float64[]
    for control in case.controls
        epsilon = reactive_smoothing_epsilon(control, 1e-6)
        for voltage in range(0.5, 1.5; length = 101)
            q = DroopOPF._smooth_droop_value(control, voltage, 1e-6, epsilon)
            push!(excursions, max(
                control.capability.q_min - q,
                q - control.capability.q_max,
                0.0,
            ))
        end
    end
    @test maximum(excursions) <= 16eps(Float64)
    @test maximum(excursions) > 0
    @test_throws ArgumentError optimize_joint_design(case; droop_q_bounds = :bad)
end


@testset "Reduced and explicit Q formulations agree on the small joint case" begin
    case = m72_case()
    policies = (
        tap_controls = [TapControl(11; lower = 0.95, upper = 1.05)],
        shunt_controls = [ShuntControl(201)],
        droop_controls = [DroopControl(2; slope_bounds = (0.04, 0.1))],
    )
    for solver in (Ipopt.Optimizer, MadNLP.Optimizer)
        explicit = optimize_joint_design(
            case;
            policies...,
            initial_state = m5_initial_state(case),
            optimizer_factory = solver,
        )
        reduced = optimize_joint_design(
            case;
            policies...,
            initial_state = m5_initial_state(case),
            optimizer_factory = solver,
            droop_q_formulation = :reduced,
        )
        @test validate_joint_design(case, explicit).valid
        @test validate_joint_design(case, reduced).valid
        @test reduced.opf.objective ≈ explicit.opf.objective atol = 1e-10
        @test reduced.opf.state.vm ≈ explicit.opf.state.vm atol = 5e-7
        @test reduced.opf.state.qg ≈ explicit.opf.state.qg atol = 5e-7
        @test reduced.taps[11] ≈ explicit.taps[11] atol = 5e-7
        @test reduced.susceptances[201] ≈ explicit.susceptances[201] atol = 5e-7
    end
end

@testset "Explicit and implied Q-bound solutions remain physically equivalent" begin
    case = m72_case()
    policies = (
        tap_controls = [TapControl(11; lower = 0.95, upper = 1.05)],
        shunt_controls = [ShuntControl(201)],
        droop_controls = [DroopControl(2; slope_bounds = (0.04, 0.1))],
    )
    for solver in (Ipopt.Optimizer, MadNLP.Optimizer)
        results = Dict(
            mode => optimize_joint_design(
                case;
                policies...,
                initial_state = m5_initial_state(case),
                optimizer_factory = solver,
                droop_q_bounds = mode,
            ) for mode in (:explicit, :implied)
        )
        @test all(validate_joint_design(case, result).valid for result in values(results))
        @test results[:implied].opf.objective ≈ results[:explicit].opf.objective atol = 1e-8
        @test results[:implied].opf.state.vm ≈ results[:explicit].opf.state.vm atol = 1e-7
        @test results[:implied].opf.state.qg ≈ results[:explicit].opf.state.qg atol = 1e-7
        @test results[:implied].taps[11] ≈ results[:explicit].taps[11] atol = 1e-7
        @test results[:implied].susceptances[201] ≈
              results[:explicit].susceptances[201] atol = 1e-7
    end
end
