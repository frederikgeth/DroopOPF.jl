using JSON, MadNLP
include(joinpath(@__DIR__,"..","examples","m7_2_case.jl"))
@testset "M7.2 simple continuous banks" begin
    c=m72_case(); start=m5_initial_state(c); ctrl=ShuntControl(201)
    @test_throws ArgumentError ShuntControl(0)
    @test_throws ArgumentError ShuntControl(201;lower=Inf)
    @test_throws ArgumentError ShuntControl(201;lower=.1,upper=0.)
    for controls in ([ShuntControl(999)],[ShuntControl(101)],[ctrl,ctrl],
        [ShuntControl(201;lower=-.01)],[ShuntControl(201;upper=.1)],
        [ShuntControl(201;upper=.01)],[ShuntControl(201;nominal=-.01)])
        @test_throws ArgumentError optimize_shunts(c,controls)
    end
    @test_throws ArgumentError optimize_shunts(m72_case(available=false),[ctrl])
    @test_throws ArgumentError optimize_shunts(m6_shunt_case(),[ctrl])
    @test_throws ArgumentError optimize_shunts(Study(c),[ctrl])
    @test_throws ArgumentError with_shunt_settings(c,Dict(201=>-.01))
    baseline=solve_opf(c;smooth_epsilon=1e-5,initial_state=start)
    fixed=optimize_shunts(c,[ShuntControl(201;lower=.02,upper=.02)];initial_state=start)
    @test validate_shunt_design(c,fixed).valid
    @test fixed.opf.objective ≈ baseline.objective atol=1e-8
    @test fixed.opf.state.vm ≈ baseline.state.vm atol=1e-5
    empty=optimize_shunts(c,ShuntControl[];initial_state=start)
    @test validate_shunt_design(c,empty).valid
    @test empty.opf.objective ≈ baseline.objective atol=1e-8
    for cap in (true,false)
        case=m72_case(capacitor=cap)
        r=optimize_shunts(case,[ctrl];initial_state=start)
        @test validate_shunt_design(case,r).valid
        metrics=shunt_design_metrics(case,r); setting=only(metrics.settings)
        @test setting.conductance ≈ setting.fractional_count*.001
        @test setting.reactive_injection ≈ r.susceptances[201]*r.opf.state.vm[3]^2
        @test setting.active_consumption ≈ setting.fractional_count*.001*r.opf.state.vm[3]^2
        replay=with_shunt_settings(case,r.susceptances)
        @test replay.network.banks[1].id == 202
        @test replay.network.banks[1].state == (1,)
        @test replay.network.branches == case.network.branches
        @test case.network.banks[1].state == (1,)
        for B in range(cap ? 0. : -.06,cap ? .06 : 0.;length=9)
            swept=with_shunt_settings(case,Dict(201=>B))
            s=solve_opf(swept;smooth_epsilon=1e-5,initial_state=start)
            @test validate_equilibrium(swept,s).valid
            @test r.opf.objective <= s.objective+1e-8
        end
        mktempdir() do dir
            path=joinpath(dir,"design.json");write_shunt_design(path,r)
            loaded=read_shunt_design(path)
            @test loaded.susceptances==r.susceptances
            @test validate_shunt_design(case,loaded).valid
            d=JSON.parsefile(path);d["schema_version"]=9;write(path,JSON.json(d))
            @test_throws ArgumentError read_shunt_design(path)
        end
    end
    joint=optimize_shunts(c,[ctrl,ShuntControl(202)];initial_state=start)
    @test validate_shunt_design(c,joint).valid
    other=optimize_shunts(c,[ctrl,ShuntControl(202)];initial_state=joint.opf.state,optimizer_factory=MadNLP.Optimizer)
    @test validate_shunt_design(c,other).valid
    @test other.opf.objective ≈ joint.opf.objective atol=1e-8
    exact=optimize_shunts(c,[ctrl,ShuntControl(202)];encoding=:complementarity,
        initial_state=joint.opf.state,optimizer_attributes=m5_ccopt_options())
    @test exact.encoding == :complementarity
    @test exact.opf.smooth_epsilon === nothing
    @test exact.complementarity_residual_max < 1e-5
    @test validate_shunt_design(c,exact).valid
    @test_throws ArgumentError optimize_shunts(c,[ctrl];encoding=:bad)
    @test_throws ArgumentError optimize_shunts(c,[ctrl];encoding=:complementarity,
        optimizer_factory=MadNLP.Optimizer)
    bad=copy(joint.susceptances);bad[201]=.08
    @test !validate_shunt_design(c,ShuntOPFResult(joint.opf,bad,joint.controls)).policy_valid
    bad=copy(joint.susceptances);delete!(bad,202)
    @test !validate_shunt_design(c,ShuntOPFResult(joint.opf,bad,joint.controls)).valid
    @test !validate_equilibrium(c,joint.opf).valid
    warm=optimize_shunts(c,[ShuntControl(201;lower=.03,upper=.04,initial=.035)];initial_state=start)
    @test validate_shunt_design(c,warm).valid
    # Direct voltage-squared verification at a fractional count, both signs.
    for cap in (true,false), v in (.9,1.,1.1)
        case=m72_case(capacitor=cap); B=cap ? .03 : -.03
        replay=with_shunt_settings(case,Dict(201=>B))
        state=ACState(fill(v,3),zeros(3),zeros(2),zeros(2))
        @test shunt_powers(replay.network,state)[2] ≈ complex(.0015,-B)*v^2
    end
    mktempdir() do dir
        path=joinpath(dir,"exact-shunt.json");write_shunt_design(path,exact)
        loaded=read_shunt_design(path)
        @test loaded.encoding == :complementarity
        @test loaded.complementarity_residual_max == exact.complementarity_residual_max
        @test validate_shunt_design(c,loaded).valid
    end
end
