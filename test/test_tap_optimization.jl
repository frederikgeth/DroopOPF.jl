using JSON, MadNLP
if !isdefined(@__MODULE__,:m6_shunt_case)
    include(joinpath(@__DIR__,"..","examples","m6_shunt_case.jl"))
end
@testset "M7.1 continuous tap design" begin
    c=m6_shunt_case(); start=m5_initial_state(c)
    for bounds in ((0.,1.),(1.1,1.),(.9,Inf),(NaN,1.))
        @test_throws ArgumentError TapControl(11;lower=bounds[1],upper=bounds[2])
    end
    @test_throws ArgumentError TapControl(11;lower=.95,upper=1.05,initial=1.1)
    @test_throws ArgumentError TapControl(11;lower=.95,upper=1.05,nominal=0.)
    ctrl=TapControl(11;lower=.95,upper=1.05,nominal=1.)
    @test_throws ArgumentError optimize_taps(c,[TapControl(99;lower=.95,upper=1.05)])
    @test_throws ArgumentError optimize_taps(c,[ctrl,ctrl])
    @test_throws ArgumentError optimize_taps(c,[TapControl(11;lower=.95,upper=1.)])
    @test_throws ArgumentError optimize_taps(scenario_case(c,Contingency(:out;branch_ids=[11])),[ctrl])
    @test_throws ArgumentError optimize_taps(Study(c),[ctrl])
    @test_throws ArgumentError with_tap_settings(c,Dict(99=>1.))
    baseline=solve_opf(c;smooth_epsilon=1e-5,initial_state=start)
    fixed=optimize_taps(c,[TapControl(11;lower=1.02,upper=1.02)];initial_state=start)
    @test validate_tap_design(c,fixed).valid
    @test fixed.opf.objective ≈ baseline.objective atol=1e-8
    @test fixed.opf.state.vm ≈ baseline.state.vm atol=1e-5
    empty=optimize_taps(c,TapControl[];initial_state=start)
    @test validate_tap_design(c,empty).valid
    @test empty.opf.objective ≈ baseline.objective atol=1e-8
    result=optimize_taps(c,[ctrl];initial_state=start)
    @test validate_tap_design(c,result).valid
    @test .95-1e-6 <= result.taps[11] <= 1.05+1e-6
    @test result.taps[22] == result.taps[33] == 1.
    @test result.opf.objective <= baseline.objective+1e-8
    @test c.network.branches[1].tap_ratio == 1.02
    metrics=tap_design_metrics(c,result)
    @test metrics.branch_active_loss >= 0
    @test metrics.settings[1].deviation_from_nominal ≈ result.taps[11]-1.
    @test metrics.settings[1].deviation_from_supplied ≈ result.taps[11]-1.02
    warm=optimize_taps(c,[TapControl(11;lower=.99,upper=1.01,initial=1.)];initial_state=start)
    @test validate_tap_design(c,warm).valid
    @test .99-1e-6 <= warm.taps[11] <= 1.01+1e-6
    replay=with_tap_settings(c,result.taps)
    @test replay.network.shunts == c.network.shunts
    @test replay.network.banks == c.network.banks
    @test DroopOPF._json_data(replay.controls) == DroopOPF._json_data(c.controls)
    @test replay.network.branches[1].phase_shift == .02
    @test minimum(operating_margins(replay.network,result.opf.state)) >= -1e-6
    @test !validate_equilibrium(c,result.opf).valid
    for tau in range(.95,1.05;length=7)
        swept=with_tap_settings(c,Dict(11=>tau))
        r=solve_opf(swept;smooth_epsilon=1e-5,initial_state=start)
        @test validate_equilibrium(swept,r).valid
        @test result.opf.objective <= r.objective+1e-8
    end
    other=optimize_taps(c,[ctrl];initial_state=result.opf.state,optimizer_factory=MadNLP.Optimizer)
    @test validate_tap_design(c,other).valid
    @test other.opf.objective ≈ result.opf.objective atol=1e-8
    exact=optimize_taps(c,[ctrl];encoding=:complementarity,initial_state=result.opf.state,
        optimizer_attributes=m5_ccopt_options())
    @test exact.encoding == :complementarity
    @test exact.opf.smooth_epsilon === nothing
    @test exact.complementarity_residual_max < 1e-5
    @test validate_tap_design(c,exact).valid
    @test_throws ArgumentError optimize_taps(c,[ctrl];encoding=:bad)
    @test_throws ArgumentError optimize_taps(c,[ctrl];encoding=:complementarity,
        optimizer_factory=MadNLP.Optimizer)
    # Explicitly treat a second branch as adjustable equipment for the two-device fixture.
    joint=optimize_taps(c,[ctrl,TapControl(22;lower=.98,upper=1.02)];initial_state=start)
    @test validate_tap_design(c,joint).valid
    @test joint.taps[33] == 1.
    @test joint.opf.objective <= result.opf.objective+1e-8
    bad=copy(result.taps); bad[22]=1.01
    @test !validate_tap_design(c,TapOPFResult(result.opf,bad,result.controls)).policy_valid
    bad=copy(result.taps); bad[11]=1.1
    @test !validate_tap_design(c,TapOPFResult(result.opf,bad,result.controls)).valid
    bad=copy(result.taps); delete!(bad,11)
    @test !validate_tap_design(c,TapOPFResult(result.opf,bad,result.controls)).valid
    mktempdir() do dir
        path=joinpath(dir,"tap.json"); write_tap_design(path,result); loaded=read_tap_design(path)
        @test loaded.taps == result.taps
        @test loaded.controls[1].nominal == 1.
        @test validate_tap_design(c,loaded).valid
        d=JSON.parsefile(path); d["schema_version"]=2; write(path,JSON.json(d))
        @test_throws ArgumentError read_tap_design(path)
    end
    mktempdir() do dir
        path=joinpath(dir,"exact-tap.json");write_tap_design(path,exact)
        loaded=read_tap_design(path)
        @test loaded.encoding == :complementarity
        @test loaded.complementarity_residual_max == exact.complementarity_residual_max
        @test validate_tap_design(c,loaded).valid
    end
end
