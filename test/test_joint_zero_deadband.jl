using MadNLP,CCOpt
@testset "S1 free slopes with a fixed zero deadband" begin
    ctrl=VoltVarDroop(VoltageSchedule(1.;v_db_low=1.,v_db_high=1.),.02,0.,
        ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.))
    c=Case("fixed-zero-width-design";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true)],Branch[]),
        generators=[Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,initial_p=.5,initial_q=.25)],
        loads=[Load(1,1;p=.5,q=.25)],controls=[ctrl],
        attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
    start=ACState([.995],[0.],[.5],[.25]);policy=DroopControl(1;slope_bounds=(.01,.04))
    @test DroopOPF._joint_droop_policy(c,policy).ranges.deadband_low==(0.,0.)
    @test_throws ArgumentError DroopOPF._joint_droop_policy(c,
        DroopControl(1;deadband_low_bounds=(0.,.01),deadband_high_bounds=(0.,.01)))
    for solver in (:ipopt,:madnlp,:ccopt)
        kwargs=solver==:ccopt ? (encoding=:complementarity,optimizer_attributes=Dict{String,Any}(
            "max_iter"=>300,"max_wall_time"=>10.,"tol"=>1e-11,"acceptable_tol"=>1e-11,
            "relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14))) :
            (optimizer_factory=solver==:ipopt ? DroopOPF.Ipopt.Optimizer : MadNLP.Optimizer,
             optimizer_attributes=Dict{String,Any}("tol"=>1e-9,"max_iter"=>300))
        audit=Ref{Any}(nothing)
        r=optimize_joint_design(c;droop_controls=[policy],initial_state=start,smooth_epsilon=1e-6,
            _measurement_hook=(phase,m)->begin
                if phase==:solved && solver==:ccopt
                    audit[]=ccopt_encoding_audit(m)
                    @test ccopt_diagnostics(m)["complementarity_pairs"]==2
                end
            end,kwargs...)
        if solver==:ccopt
            @test all(row["voltage_hinges_eliminated"] for row in audit[]["controllers"])
            @test audit[]["max_raw_droop_error_pu"] < 1e-8
        end
        check=validate_joint_design(c,r)
        # Degenerate one-bus design has a continuum of slope/voltage optima;
        # test physical support independently of the backend termination label.
        @test check.policy_valid && !isnothing(check.physical) && check.physical.valid
        println("fixed-zero-deadband ",solver," status=",r.opf.termination_status)
        @test r.droops[1].deadband_low==r.droops[1].deadband_high==0.
        frozen=DroopOPF._joint_droop_case(c,r)
        gate=check_feasibility(FeasibilityProblem(frozen);witnesses=[FeasibilityWitness(r.opf.state)],solve_missing=false)
        @test gate.status==:feasible
    end
end

using JuMP
@testset "Zero-deadband specialization and smooth derivatives" begin
    cap=ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.)
    ctrl=VoltVarDroop(VoltageSchedule(1.;v_db_low=1.,v_db_high=1.),.02,.1,cap)
    function zero_model(control; initial_state=nothing)
        c=Case("zero-specialization";base_power=100.,base_frequency=50.,
            network=ACNetwork([Bus(1;reference=true)],Branch[]),
            generators=[Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.)],
            loads=[Load(1,1;p=.5,q=.25)],controls=[control],
            attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
        DroopOPF._build_complementarity_opf_model(c;silent=true,initial_state)
    end
    model,v=zero_model(ctrl)
    wide=VoltVarDroop(VoltageSchedule(1.;v_db_low=.999,v_db_high=1.001),.02,.1,cap)
    general,w=zero_model(wide)
    @test isempty(v.voltage_lower) && isempty(v.voltage_upper)
    @test length(w.voltage_lower)==length(w.voltage_upper)==1
    @test num_variables(general)-num_variables(model)==4
    @test num_constraints(general;count_variable_in_set_constraints=false)-
        num_constraints(model;count_variable_in_set_constraints=false)==4
    mixed=Case("mixed-deadbands";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true)],Branch[]),
        generators=[Generator(i,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.) for i in 1:2],
        loads=[Load(1,1;p=.5,q=.25)],controls=[ctrl,wide],
        attachments=[GeneratorControlAttachment(i,i,RegulatedLocation(:bus,1)) for i in 1:2])
    _,mixedvars=DroopOPF._build_complementarity_opf_model(mixed;silent=true)
    @test collect(keys(mixedvars.voltage_lower))==[2]
    @test collect(keys(mixedvars.voltage_upper))==[2]
    @test length(mixedvars.raw_q)==2
    # Check the actual encoded raw equality and projection KKT at exact
    # witnesses, including both knees, tails, and the former deadband center.
    for raw in (-2.,-1.,-.25,.1,.5,1.,2.)
        voltage=1.0 + .02*(.1-raw);q=clamp(raw,-1.,1.)
        m,z=zero_model(ctrl;initial_state=ACState([voltage],[0.],[.5],[q]))
        @test start_value(z.raw_q[1]) ≈ raw atol=1e-12
        @test start_value(z.qg[1]) ≈ q atol=1e-12
        e=JuMP.NLPEvaluator(m);JuMP.MOI.initialize(e,[:Jac])
        residuals=zeros(num_nonlinear_constraints(m))
        JuMP.MOI.eval_constraint(e,residuals,start_value.(all_variables(m)))
        @test abs(last(residuals)) < 1e-12
        @test start_value(z.q_lower_slack[1])*start_value(z.q_lower_multiplier[1]) == 0.
        @test start_value(z.q_upper_slack[1])*start_value(z.q_upper_multiplier[1]) == 0.
        @test abs(q-start_value(z.raw_q[1])-start_value(z.q_lower_multiplier[1])+
            start_value(z.q_upper_multiplier[1])) < 1e-12
    end
    # A design variable whose start is zero is not a constant zero width.
    @variable(model, width>=0, start=0.)
    @test !DroopOPF._fixed_zero_deadband(width,0.)
    @test !DroopOPF._fixed_zero_deadband(0.,1e-15)

    function smooth_expression_model(legacy)
        m=Model()
        @variable(m, voltage)
        @variable(m, slope)
        @variable(m, reference)
        params=(v_ref=reference,slope=slope,deadband_low=0.,deadband_high=0.)
        response=if legacy
            JuMP.register(m,:spv,1,z->DroopOPF._smooth_positive(z,1e-4);autodiff=true)
            JuMP.register(m,:spq,1,z->DroopOPF._smooth_positive(z,1e-3);autodiff=true)
            raw=:(0.1+(spv($reference-$voltage)-spv($voltage-$reference))/$slope)
            :(-1.0 + spq($raw + 1.0) - spq($raw - 1.0))
        else
            DroopOPF._smooth_droop_expression!(m,"zero",ctrl,voltage,params,1e-4,1e-3)
        end
        JuMP.set_nonlinear_objective(m,JuMP.MOI.MIN_SENSE,response)
        e=JuMP.NLPEvaluator(m);JuMP.MOI.initialize(e,[:Grad,:Hess])
        e
    end
    old=smooth_expression_model(true);new=smooth_expression_model(false)
    # Interior, reference, both saturation knees, and saturated tails.
    for slope in (.01,.02,.04), raw in (-2.,-1.,-.25,.1,.5,1.,2.)
        voltage=1.0 + slope*(.1-raw);x=[voltage,slope,1.]
        @test JuMP.MOI.eval_objective(new,x) ≈ JuMP.MOI.eval_objective(old,x) atol=1e-12
        gradients=[zeros(3),zeros(3)]
        for (e,g) in zip((old,new),gradients);JuMP.MOI.eval_objective_gradient(e,g,x);end
        @test gradients[1] ≈ gradients[2] atol=1e-9 rtol=1e-10
        hessians=Matrix{Float64}[]
        for e in (old,new)
            structure=JuMP.MOI.hessian_lagrangian_structure(e);vals=zeros(length(structure))
            JuMP.MOI.eval_hessian_lagrangian(e,vals,x,1.,Float64[])
            H=zeros(3,3)
            for ((i,j),a) in zip(structure,vals);H[i,j]=H[j,i]=a;end
            push!(hessians,H)
        end
        @test hessians[1] ≈ hessians[2] atol=1e-6 rtol=1e-9
        # Scalar paths must match the expression and the exact clipped curve.
        scalar=DroopOPF._smooth_droop_value(ctrl,voltage,slope,1.,0.,0.,1e-4,1e-3)
        @test scalar ≈ JuMP.MOI.eval_objective(new,x) atol=1e-12
        if slope==ctrl.slope
            @test DroopOPF._smooth_droop_value(ctrl,voltage,1e-4,1e-3) ≈ scalar atol=1e-12
        end
        @test abs(scalar-clamp(raw,-1.,1.)) <= 1e-3*log(2)+1e-12
    end
end
