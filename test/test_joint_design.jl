using JSON, MadNLP
if !isdefined(@__MODULE__,:m72_case)
    include(joinpath(@__DIR__,"..","examples","m7_2_case.jl"))
end
@testset "M7.3 joint equipment/droop design" begin
    c=m72_case();start=m5_initial_state(c)
    tap=[TapControl(11;lower=.95,upper=1.05)]
    shunt=[ShuntControl(201)]
    droop=[DroopControl(2;slope_bounds=(.04,.1))]
    @test_throws ArgumentError optimize_joint_design(Study(c))
    @test_throws ArgumentError optimize_joint_design(c;droop_controls=[DroopControl(99)])
    @test_throws ArgumentError optimize_joint_design(c;droop_controls=[droop;droop])
    @test_throws ArgumentError optimize_joint_design(c;droop_controls=[DroopControl(2;slope_bounds=(-1.,1.))])
    @test_throws ArgumentError optimize_joint_design(c;droop_controls=[DroopControl(2;deadband_low_bounds=(0.,.01),deadband_high_bounds=(0.,.01))])
    results=Dict()
    for t in (false,true), s in (false,true), d in (false,true)
        r=optimize_joint_design(c;tap_controls=t ? tap : TapControl[],shunt_controls=s ? shunt : ShuntControl[],droop_controls=d ? droop : DroopControl[],initial_state=start)
        results[(t,s,d)]=r
        @test validate_joint_design(c,r).valid
        @test validate_equilibrium(with_joint_settings(c,r),r.opf).valid
        m=joint_design_metrics(c,r)
        @test m.objective_recomputed ≈ r.opf.objective atol=1e-10
        @test m.design_penalty==0
        @test r.taps[22]==r.taps[33]==1.
        @test c.network.banks[1].state==(1,)
    end
    base=solve_opf(c;smooth_epsilon=1e-5,initial_state=start)
    @test results[(false,false,false)].opf.objective ≈ base.objective atol=1e-8
    @test results[(true,false,false)].opf.objective ≈ optimize_taps(c,tap;initial_state=start).opf.objective atol=1e-8
    @test results[(false,true,false)].opf.objective ≈ optimize_shunts(c,shunt;initial_state=start).opf.objective atol=1e-8
    study=Study(c);reference=solve_scopf(study;smooth_epsilon=1e-5,initial_states=Dict(:base=>start))
    m3=optimize_droop_parameters(study,2;slope_bounds=(.04,.1),reference_result=reference)
    matched=optimize_joint_design(c;droop_controls=droop,initial_state=reference.states[:base])
    @test validate_joint_design(c,matched).valid
    @test matched.opf.objective ≈ m3.result.objective atol=1e-8
    r=results[(true,true,true)]
    @test r.opf.objective <= minimum(x.opf.objective for x in values(results))+1e-8
    mad=optimize_joint_design(c;tap_controls=tap,shunt_controls=shunt,droop_controls=droop,initial_state=r.opf.state,optimizer_factory=MadNLP.Optimizer)
    @test validate_joint_design(c,mad).valid
    @test mad.opf.objective ≈ r.opf.objective atol=1e-8
    exact=optimize_joint_design(c;tap_controls=tap,shunt_controls=shunt,
        encoding=:complementarity,initial_state=r.opf.state,
        optimizer_attributes=m5_ccopt_options())
    @test exact.encoding == :complementarity
    @test exact.opf.smooth_epsilon === nothing
    @test exact.complementarity_residual_max < 1e-5
    @test validate_joint_design(c,exact).valid
    @test validate_equilibrium(with_joint_settings(c,exact),exact.opf).valid
    exact_audit=exact_droop_audit(c,exact)
    @test exact_audit["max_residual_pu"] < 1e-5
    @test exact_audit["max_ratio_to_tolerance"] < 1
    @test exact_audit["worst"]["within_tolerance"]
    @test Set(keys(exact.taps)) == Set(b.id for b in c.network.branches)
    @test Set(keys(exact.susceptances)) == Set([201])
    @test_throws ArgumentError optimize_joint_design(c;encoding=:bad)
    exact_droop=[DroopControl(2;slope_bounds=(.04,.1),v_ref_bounds=(.995,1.005),
        deadband_low_bounds=(.005,.015),deadband_high_bounds=(.005,.015))]
    exact_diagnostics=Ref{Any}(nothing);exact_model=Ref{Any}(nothing)
    exact_all=optimize_joint_design(c;tap_controls=tap,shunt_controls=shunt,
        droop_controls=exact_droop,encoding=:complementarity,initial_state=r.opf.state,
        optimizer_attributes=m5_ccopt_options(),
        _measurement_hook=(phase,model)->phase==:solved && begin
            exact_model[]=model;exact_diagnostics[]=ccopt_diagnostics(model)
        end)
    @test exact_all.encoding == :complementarity
    @test Set(keys(exact_all.droops)) == Set([2])
    @test .04 <= exact_all.droops[2].slope <= .1
    @test .995 <= exact_all.droops[2].v_ref <= 1.005
    @test .005 <= exact_all.droops[2].deadband_low <= .015
    @test .005 <= exact_all.droops[2].deadband_high <= .015
    @test exact_all.complementarity_residual_max < 1e-5
    @test validate_joint_design(c,exact_all).valid
    @test exact_diagnostics[]["inner_iterations"] > 0
    @test exact_diagnostics[]["outer_iterations"] === nothing
    @test exact_diagnostics[]["complementarity_pairs"] == 8
    @test exact_diagnostics[]["complementarity_feasibility"] < 1e-5
    encoding_audit=ccopt_encoding_audit(exact_model[])
    @test encoding_audit["max_exact_droop_error_pu"] < 1e-5
    @test encoding_audit["max_raw_droop_error_pu"] < 1e-5
    @test_throws ArgumentError optimize_joint_design(c;encoding=:complementarity,
        droop_q_bounds=:implied)
    @test_throws ArgumentError optimize_joint_design(c;encoding=:complementarity,
        droop_q_formulation=:reduced)
    @test_throws ArgumentError optimize_joint_design(c;encoding=:complementarity,
        optimizer_factory=MadNLP.Optimizer)
    # Independently selectable references and widths, including more than one controller.
    for field in (:v_ref_bounds,:deadband_low_bounds,:deadband_high_bounds)
        bounds=field==:v_ref_bounds ? (.995,1.005) : (.005,.015)
        control=DroopControl(2;NamedTuple{(field,)}((bounds,))...)
        x=optimize_joint_design(c;tap_controls=tap,shunt_controls=shunt,droop_controls=[control,DroopControl(1;slope_bounds=(.04,.07))],initial_state=start)
        @test validate_joint_design(c,x).valid
        @test x.droops[2].slope==c.controls[2].slope
    end
    bad=copy(r.taps);bad[22]=1.01
    @test !validate_joint_design(c,JointDesignResult(r.opf,bad,r.susceptances,r.droops,r.tap_controls,r.shunt_controls,r.droop_controls)).tap_policy_valid
    tiny=copy(r.susceptances);tiny[201]=-1e-10
    @test !validate_joint_design(c,JointDesignResult(r.opf,r.taps,tiny,r.droops,r.tap_controls,r.shunt_controls,r.droop_controls)).valid
    bads=copy(r.susceptances);bads[201]=.08
    @test !validate_joint_design(c,JointDesignResult(r.opf,r.taps,bads,r.droops,r.tap_controls,r.shunt_controls,r.droop_controls)).shunt_policy_valid
    badd=copy(r.droops);badd[2]=DroopSettings(.2,1.,.01,.01)
    @test !validate_joint_design(c,JointDesignResult(r.opf,r.taps,r.susceptances,badd,r.tap_controls,r.shunt_controls,r.droop_controls)).droop_policy_valid
    @test !validate_equilibrium(c,r.opf).valid
    mktempdir() do dir
        path=joinpath(dir,"joint.json");write_joint_design(path,r);loaded=read_joint_design(path)
        @test validate_joint_design(c,loaded).valid
        @test loaded.taps==r.taps
        @test loaded.susceptances==r.susceptances
        @test loaded.droops[2].slope==r.droops[2].slope
        d=JSON.parsefile(path);d["schema_version"]=99;write(path,JSON.json(d))
        @test_throws ArgumentError read_joint_design(path)
    end
    mktempdir() do dir
        path=joinpath(dir,"exact-joint.json");write_joint_design(path,exact)
        loaded=read_joint_design(path)
        @test loaded.encoding == :complementarity
        @test loaded.complementarity_residual_max == exact.complementarity_residual_max
        @test validate_joint_design(c,loaded).valid
    end
end
