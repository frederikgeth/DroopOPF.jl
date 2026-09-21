include(joinpath(@__DIR__,"..","examples","s1_public_recovery.jl"))

@testset "S1 public overlays and smoothing budget" begin
    source=joinpath(@__DIR__,"data","droop2.m")
    original=load_matpower_case(source)
    baseline=optimize_joint_design(original;optimizer_attributes=Dict("bound_relax_factor"=>0.))
    @test validate_joint_design(original,baseline).valid
    case,p,metadata=s1_public_overlay(original,baseline,source;bank_count=1)
    @test length(case.controls)==1
    @test length(case.network.banks)==1
    @test isempty(p.tap_controls) # TAP=0 is not silently made adjustable.
    @test isempty(original.controls) && isempty(original.network.banks)
    @test case.generators==original.generators
    @test case.network.branches==original.network.branches
    @test case.network.shunts==original.network.shunts
    @test bank_admittance(only(case.network.banks))==0
    @test validate_equilibrium(case,baseline.opf).valid
    @test metadata["kind"]=="synthetic study overlay, not measured equipment"
    stressed=s1_load(case,1.05)
    @test only(stressed.loads).p≈1.05*only(case.loads).p
    @test stressed.generators==case.generators &&
        [(c.slope,c.schedule,c.q_at_deadband,c.capability) for c in stressed.controls]==
        [(c.slope,c.schedule,c.q_at_deadband,c.capability) for c in case.controls]
    @test only(case.loads).p==only(original.loads).p
    budget=s1_epsilon_bound(case,p)
    @test 0<budget.epsilon<=1e-6
    @test budget.max_curve_gap<=1.000001e-6
    @test_throws ArgumentError s1_epsilon_bound(case,p;fraction=1.)
    c=only(case.controls);bounds=DroopOPF._joint_droop_policy(case,only(p.droop_controls)).ranges.slope
    qscale=min(c.q_at_deadband-c.capability.q_min,c.capability.q_max-c.q_at_deadband)
    observed_gap=0.
    for slope in bounds
        knees=[c.schedule.v_db_low,c.schedule.v_db_high,
            c.schedule.v_db_low-slope*(c.capability.q_max-c.q_at_deadband),
            c.schedule.v_db_high+slope*(c.q_at_deadband-c.capability.q_min)]
        voltages=vcat(collect(range(.8,1.2;length=101)),[v+offset*budget.epsilon for v in knees for offset in (-1,0,1)])
        for voltage in voltages
            reference=clamp(c.q_at_deadband+(max(c.schedule.v_db_low-voltage,0)-max(voltage-c.schedule.v_db_high,0))/slope,c.capability.q_min,c.capability.q_max)
            smooth=DroopOPF._smooth_droop_value(c,voltage,slope,c.schedule.v_ref,
                c.schedule.v_ref-c.schedule.v_db_low,c.schedule.v_db_high-c.schedule.v_ref,
                budget.epsilon,budget.epsilon*qscale)
            observed_gap=max(observed_gap,abs(smooth-reference))
            @test abs(smooth-reference)<=budget.max_curve_gap+1e-12
        end
    end
    @test observed_gap>0.
    audit=s1_source_audit(case,JointDesignResult(baseline.opf,baseline.taps,Dict{Int,Float64}(),
        Dict{Int,DroopSettings{Float64}}(),TapControl[],ShuntControl[],DroopControl[]),source)
    @test audit["source_angle_violation_degrees"]==0
    @test s1_source_audit(case,nothing,source)===nothing
end

@testset "S1 MadNLP and experiment records" begin
    case=m72_case()
    p=(tap_controls=[TapControl(11;lower=.95,upper=1.05)],shunt_controls=[ShuntControl(201)],
        droop_controls=[DroopControl(2;slope_bounds=(.04,.1))])
    initial=s1_reseed(case,p;fraction=.2)
    @test only(initial.tap_controls).initial≈.97
    @test only(initial.droop_controls).initial.slope≈.052
    mktempdir() do out
        row,r=s1_attempt(out,"small-mad",case,s1_flat(case);policies=initial,solver=:madnlp)
        # A cold-start solve may fail; the recorder must report that honestly.
        @test row["valid"]==validate_joint_design(case,r).valid
        @test !isempty(row["trace"])
        @test all(isfinite(x["native_dual"]) && isfinite(x["native_complementarity"]) for x in row["trace"])
        @test row["model"]["final_native"]["iterations"]==row["iterations"]
        @test all(row[k]>=0 for k in ("build_seconds","solve_seconds","extract_seconds","validate_seconds"))
        @test row["process_lifetime_peak_rss_bytes"]>0
        @test isfile(joinpath(out,"small-mad-start.json"))
        @test validate_joint_design(case,read_joint_design(joinpath(out,"small-mad-design.json"))).valid==row["valid"]
        failed,_=s1_attempt(out,"limited",case,s1_flat(case);policies=p,options=Dict("max_iter"=>0))
        @test !failed["valid"]
        @test failed["status"]=="ITERATION_LIMIT"
        @test isfile(joinpath(out,"limited-diagnostics.json"))
        seeded=s1_reseed(case,p;result=r)
        @test only(seeded.tap_controls).initial==r.taps[11]
        simple=load_matpower_case(joinpath(@__DIR__,"data","droop2.m"))
        success,_=s1_attempt(out,"simple-mad",simple,s1_flat(simple);solver=:madnlp)
        @test success["valid"]
        s1_summary(out,[row,failed])
        @test length(JSON.parsefile(joinpath(out,"summary.json")))==2
    end
    public=load_matpower_case(joinpath(@__DIR__,"data","pglib","v23.07","pglib_opf_case300_ieee.m"))
    @test length(public.network.buses)==300
    @test length(public.generators)==69
    @test length(public.network.branches)==411
end

@testset "S1 physical failure locations agree with independent validation" begin
    source=joinpath(@__DIR__,"data","droop2.m")
    original=load_matpower_case(source)
    baseline=optimize_joint_design(original;optimizer_attributes=Dict("bound_relax_factor"=>0.))
    case,p,_=s1_public_overlay(original,baseline,source;bank_count=1)
    state=baseline.opf.state
    @test isempty(s1_failure_details(case,state))
    vm=copy(state.vm);pg=copy(state.pg);qg=copy(state.qg)
    vm[1]=case.network.buses[1].v_max+0.05
    pg[1]=case.generators[1].p_max+0.1
    qg[1]=case.generators[1].q_max+0.1
    perturbed=ACState(vm,state.va,pg,qg)
    details=s1_failure_details(case,perturbed)
    check=validate_equilibrium(case,perturbed)
    @test Set(Symbol(d["category"]) for d in details)==Set(check.violations)
    @test all(d["exceedance_pu"]>0 for d in details)
    @test any(d["category"]=="voltage_max" && d["id"]==case.network.buses[1].id for d in details)
    @test any(d["category"]=="generator_p_max" && d["id"]==case.generators[1].id for d in details)
    @test any(d["category"]=="droop" && occursin("regulated bus",d["component"]) for d in details)
    loose=s1_failure_details(case,perturbed;power_tolerance=1e9,droop_tolerance=1e9,limit_tolerance=1e9)
    @test isempty(loose)
end
