using DroopOPF, JuMP, Ipopt, MadNLP, JSON, LinearAlgebra

function s1_saturation_model(solver, mode, target_voltage; epsilon = 1e-6)
    mode in (:explicit, :implied) || throw(ArgumentError("unknown Q-bound mode"))
    schedule = VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01)
    capability = ReactiveCapability(
        p_min = 0.0,
        p_max = 1.0,
        q_min = -0.5,
        q_max = 0.5,
    )
    control = VoltVarDroop(schedule, 0.05, 0.0, capability)
    reactive_epsilon = reactive_smoothing_epsilon(control, epsilon)
    model = Model(solver)
    set_silent(model)
    @variable(model, 0.8 <= voltage <= 1.2, start = target_voltage)
    @variable(model, reactive, start = DroopOPF._smooth_droop_value(
        control,
        target_voltage,
        epsilon,
        reactive_epsilon,
    ))
    if mode == :explicit
        set_lower_bound(reactive, capability.q_min)
        set_upper_bound(reactive, capability.q_max)
    end
    JuMP.register(
        model,
        :s1_reproducer_droop,
        1,
        v -> DroopOPF._smooth_droop_value(control, v, epsilon, reactive_epsilon);
        autodiff = true,
    )
    droop = @NLconstraint(model, reactive == s1_reproducer_droop(voltage))
    @objective(model, Min, (voltage - target_voltage)^2 + 1e-3 * reactive^2)
    optimize!(model)

    x = value.([voltage, reactive])
    evaluator = JuMP.NLPEvaluator(model)
    JuMP.MOI.initialize(evaluator, [:Jac])
    entries = zeros(length(JuMP.MOI.jacobian_structure(evaluator)))
    JuMP.MOI.eval_constraint_jacobian(evaluator, entries, x)
    structure = JuMP.MOI.jacobian_structure(evaluator)
    droop_gradient = zeros(2)
    for ((row, column), entry) in zip(structure, entries)
        row == 1 && (droop_gradient[column] = entry)
    end
    active_q_gradient = [0.0, 1.0]
    stacked = vcat(droop_gradient', active_q_gradient')
    singular_values = svdvals(stacked)
    q_bound_dual = mode == :explicit ? (
        lower = dual(LowerBoundRef(reactive)),
        upper = dual(UpperBoundRef(reactive)),
    ) : nothing
    return Dict(
        "solver" => solver == Ipopt.Optimizer ? "ipopt" : "madnlp",
        "mode" => string(mode),
        "target_voltage" => target_voltage,
        "termination" => string(termination_status(model)),
        "voltage" => value(voltage),
        "reactive" => value(reactive),
        "objective" => objective_value(model),
        "droop_dual" => dual(droop),
        "q_bound_dual" => q_bound_dual,
        "droop_gradient" => droop_gradient,
        "stacked_with_q_bound_singular_values" => singular_values,
        "parallel_to_q_bound" => abs(droop_gradient[1]) <= 1e-10,
        "physical_q_margin" => min(
            value(reactive) - capability.q_min,
            capability.q_max - value(reactive),
        ),
    )
end

function s1_saturation_reproducer(out)
    mkpath(out)
    rows = [
        s1_saturation_model(solver, mode, target)
        for solver in (Ipopt.Optimizer, MadNLP.Optimizer)
        for mode in (:explicit, :implied)
        for target in (0.8, 1.0, 1.2)
    ]
    write(joinpath(out, "summary.json"), JSON.json(rows; pretty = true))
    return rows
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_saturation_reproducer(abspath(ARGS[1]))
