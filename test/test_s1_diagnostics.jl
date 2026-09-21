using JuMP, LinearAlgebra
include(joinpath(@__DIR__, "..", "examples", "s1_diagnostics.jl"))

@testset "S1 smooth droop values and exact derivatives" begin
    control=m72_case().controls[1]
    settings=DroopSettings(control)
    ev=1e-5; eq=DroopOPF.reactive_smoothing_epsilon(control,ev)
    model=Model()
    @variable(model,x[1:5])
    parameters=(slope=x[2],v_ref=x[3],deadband_low=x[4],deadband_high=x[5])
    expression=DroopOPF._smooth_droop_expression!(model,:s1_curve,control,x[1],parameters,ev,eq)
    JuMP.add_nonlinear_constraint(model,Expr(:call,:(==),expression,0.))
    evaluator=JuMP.NLPEvaluator(model);moi=JuMP.MOI
    @test :Hess in moi.features_available(evaluator)
    moi.initialize(evaluator,[:Jac,:Hess])
    jac_structure=moi.jacobian_structure(evaluator)
    hess_structure=moi.hessian_lagrangian_structure(evaluator)
    function gradient(z)
        values=zeros(length(jac_structure));moi.eval_constraint_jacobian(evaluator,values,z)
        g=zeros(5)
        for ((i,j),v) in zip(jac_structure,values)
            g[j]=v
        end
        g
    end
    low=settings.v_ref-settings.deadband_low;high=settings.v_ref+settings.deadband_high
    voltages=[.85,low-settings.slope*(control.capability.q_max-control.q_at_deadband),
        low-ev,low,low+ev,settings.v_ref,high-ev,high,high+ev,
        high+settings.slope*(control.q_at_deadband-control.capability.q_min),1.15]
    h=min(ev,eq*settings.slope)/100
    for voltage in voltages
        z=[voltage,settings.slope,settings.v_ref,settings.deadband_low,settings.deadband_high]
        values=zeros(1);moi.eval_constraint(evaluator,values,z)
        reference(w)=DroopOPF._smooth_droop_value(control,w...,ev,eq)
        @test values[1] ≈ reference(z) atol=1e-12
        fd=zeros(5);Hfd=zeros(5,5)
        for j in 1:5
            plus=copy(z);minus=copy(z);plus[j]+=h;minus[j]-=h
            fd[j]=(reference(plus)-reference(minus))/(2h)
            Hfd[:,j]=(gradient(plus)-gradient(minus))/(2h)
        end
        @test norm(gradient(z)-fd,Inf)/max(1.,norm(fd,Inf)) < 1e-4
        hv=zeros(length(hess_structure));moi.eval_hessian_lagrangian(evaluator,hv,z,0.,[1.])
        H=zeros(5,5)
        for ((i,j),v) in zip(hess_structure,hv)
            H[i,j]=H[j,i]=v
        end
        @test norm(H-Hfd,Inf)/max(1.,norm(Hfd,Inf)) < 1e-4
    end
end

@testset "S1 read-only convergence recorder" begin
    trace=[];bounds=[];metadata=Dict{String,Any}();phases=Symbol[]
    recorder=s1_recorder(trace,bounds,metadata)
    c=m72_case()
    hook=(phase,model)->begin push!(phases,phase);recorder(phase,model) end
    r=optimize_joint_design(c;initial_state=m5_initial_state(c),
        tap_controls=[TapControl(11;lower=.95,upper=1.05)],
        droop_controls=[DroopControl(2;slope_bounds=(.04,.1))],_measurement_hook=hook)
    @test validate_joint_design(c,r).valid
    @test phases==[:built,:solved,:extracted]
    @test !isempty(trace) && !isempty(bounds)
    @test "Hess" in metadata["nonlinear_derivative_features"]
    @test all(!haskey(row,"violation_query_error") for row in trace)
    @test all(all(isfinite(row[key]) for key in ("unscaled_stationarity","unscaled_complementarity","unscaled_constraint_violation","unscaled_bound_violation")) for row in trace)
    @test trace[end]["unscaled_constraint_violation"]<1e-6
end
