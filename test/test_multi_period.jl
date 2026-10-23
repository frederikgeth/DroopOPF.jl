using JuMP
isdefined(@__MODULE__,:m72_case) || include(joinpath(@__DIR__,"..","examples","m7_2_case.jl"))
@testset "P3 multi-period shared droop and ramp coupling" begin
    c=m72_case(); scaled(f)=DroopOPF._feasibility_scaled_case(c,f)
    cases=[scaled(.9),scaled(1.1),scaled(.95)]
    ramps=Dict(7=>(0.,0.),9=>(.5,.5))
    study=MultiPeriodStudy(cases;duration_hours=[.5,1.,2.],ramp_limits=ramps)
    opts=Dict("tol"=>1e-9,"bound_relax_factor"=>0.,"max_cpu_time"=>20.)
    starts=[m5_initial_state(x) for x in cases]
    fixed=optimize_multi_period(study;initial_states=starts,optimizer_attributes=opts)
    audit=validate_multi_period(study,fixed)
    @test audit.valid
    @test audit.objective_error_mwh < 1e-8
    @test audit.ramp_violation < 1e-7
    @test maximum(r.state.pg[1] for r in fixed.periods)-minimum(r.state.pg[1] for r in fixed.periods) < 1e-7
    @test abs(fixed.periods[2].state.pg[2]-fixed.periods[1].state.pg[2]) > .05
    droops=[DroopControl(2;slope_bounds=(.04,.1),v_ref_bounds=(.99,1.01))]
    designed=optimize_multi_period(study;droop_controls=droops,
        initial_states=[r.state for r in fixed.periods],optimizer_attributes=opts)
    @test validate_multi_period(study,designed).valid
    @test Set(keys(designed.droops))==Set([2])
    @test designed.objective_mwh <= fixed.objective_mwh+1e-6
    @test designed.objective_mwh ≈ sum(study.duration_hours[t]*r.objective for (t,r) in enumerate(designed.periods)) atol=1e-8
    uncoupled=optimize_multi_period(MultiPeriodStudy(cases;duration_hours=[.5,1.,2.]);
        initial_states=[r.state for r in fixed.periods],optimizer_attributes=opts)
    @test validate_multi_period(MultiPeriodStudy(cases;duration_hours=[.5,1.,2.]),uncoupled).valid
    @test uncoupled.objective_mwh <= fixed.objective_mwh+1e-6
    @test validate_multi_period(study,uncoupled).ramp_violation > 1e-4
    # A single period reproduces the ordinary joint AC loss problem.
    joint=optimize_joint_design(c;initial_state=starts[1],optimizer_attributes=opts,
        smooth_epsilon=1e-6,_measurement_hook=(phase,m)->begin
            if phase==:built
                pg=[variable_by_name(m,"pg[$i]") for i in eachindex(c.generators)]
                @objective(m,Min,c.base_power*(sum(pg)-sum(l.p for l in c.loads)))
            end
        end)
    single=optimize_multi_period(MultiPeriodStudy([c];duration_hours=[2.]);
        initial_states=[joint.opf.state],optimizer_attributes=opts)
    @test validate_multi_period(MultiPeriodStudy([c];duration_hours=[2.]),single).valid
    @test single.objective_mwh ≈ 2joint.opf.objective atol=1e-6
    # Independent replay catches an inter-period violation even though each AC
    # equilibrium remains valid, as well as corrupt objectives and shared curves.
    zero=MultiPeriodStudy(cases;duration_hours=[.5,1.,2.],ramp_limits=Dict(9=>(0.,0.)))
    @test !validate_multi_period(zero,designed).valid
    @test validate_multi_period(zero,designed).ramp_violation > .05
    bad=MultiPeriodResult(designed.periods,designed.droops,designed.droop_controls,
        designed.objective_mwh+1.,designed.termination_status,designed.primal_status)
    @test !validate_multi_period(study,bad).valid
    missing=MultiPeriodResult(designed.periods[1:2],designed.droops,designed.droop_controls,
        designed.objective_mwh,designed.termination_status,designed.primal_status)
    @test !validate_multi_period(study,missing).valid
    badcurves=copy(designed.droops);badcurves[2]=DroopSettings(.2,1.,.01,.01)
    @test !validate_multi_period(study,MultiPeriodResult(designed.periods,badcurves,
        designed.droop_controls,designed.objective_mwh,designed.termination_status,designed.primal_status)).valid
    damaged=deepcopy(designed)
    damaged.periods[2].state.qg[1]+=.01
    @test !validate_multi_period(study,damaged).valid
    rejected=MultiPeriodResult(designed.periods,designed.droops,designed.droop_controls,
        designed.objective_mwh,:TIME_LIMIT,designed.primal_status)
    @test !validate_multi_period(study,rejected).valid
    wrongperiod=copy(designed.periods);p=wrongperiod[1]
    wrongperiod[1]=DroopOPF.ACOPFResult{Float64}(p.state,p.objective+1.,p.termination_status,
        p.primal_status,p.smooth_epsilon,p.smooth_reactive_relative_epsilon,p.smooth_reactive_epsilon)
    @test !validate_multi_period(study,MultiPeriodResult(wrongperiod,designed.droops,
        designed.droop_controls,designed.objective_mwh,designed.termination_status,designed.primal_status)).valid
    angles=MultiPeriodStudy(cases;duration_hours=[.5,1.,2.],angle_limits=Dict(11=>(0.,0.)))
    @test validate_multi_period(angles,designed).angle_violation > 1e-4
    @test_throws ArgumentError MultiPeriodStudy(Case[])
    @test_throws ArgumentError MultiPeriodStudy(cases;duration_hours=[1.])
    @test_throws ArgumentError MultiPeriodStudy(cases;duration_hours=[1.,0.,1.])
    @test_throws ArgumentError MultiPeriodStudy(cases;ramp_limits=Dict(999=>(1.,1.)))
    @test_throws ArgumentError MultiPeriodStudy(cases;ramp_limits=Dict(7=>(-1.,1.)))
    @test_throws ArgumentError MultiPeriodStudy(cases;ramp_limits=Dict(7=>(Inf,1.)))
    @test_throws ArgumentError MultiPeriodStudy(cases;angle_limits=Dict(999=>(-1.,1.)))
    @test_throws ArgumentError MultiPeriodStudy([c,with_tap_settings(c,Dict(11=>1.03))])
    @test_throws ArgumentError optimize_multi_period(study;initial_states=[starts[1]])
    @test_throws ArgumentError optimize_multi_period(study;droop_controls=[droops;droops])
    @test_throws ArgumentError optimize_multi_period(study;smooth_epsilon=NaN)
    # Non-unit durations affect ramp allowances, independently from energy weights.
    d=abs(designed.periods[2].state.pg[2]-designed.periods[1].state.pg[2])
    long=MultiPeriodStudy(cases;duration_hours=[2.,1.,2.],ramp_limits=Dict(9=>(d,d)))
    short=MultiPeriodStudy(cases;duration_hours=[.5,1.,2.],ramp_limits=Dict(9=>(d,d)))
    @test validate_multi_period(long,designed).ramp_violation <= 1e-6
    @test validate_multi_period(short,designed).ramp_violation >= d/2-1e-6
end
