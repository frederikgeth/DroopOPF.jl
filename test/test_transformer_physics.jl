using JuMP, Ipopt, MadNLP
include(joinpath(@__DIR__, "..", "examples", "m5_transformer_case.jl"))

@testset "M5.2-M5.3 analytical transformer physics" begin
    buses=[Bus(1;reference=true),Bus(2)]
    state=ACState(ones(2),zeros(2),Float64[],Float64[])
    for ratio in (0.9,1.,1.1)
        net=ACNetwork(buses,[Branch(1,1,2;resistance=0.,reactance=.1,thermal_limit=10.,tap_ratio=ratio)])
        flow=branch_flows(net,state)
        @test flow.from[1] ≈ 10im*(1/ratio^2-1/ratio) atol=1e-12
        @test flow.to[1] ≈ 10im*(1-1/ratio) atol=1e-12
    end
    # Hand fixture: a=2j, Vf=2j, Vt=.9+.1j, z=.1+.2j, b=.2.
    # Internal voltage=1, series current=-.2-.6j, If=.25-.1j, It=.19+.69j.
    net=ACNetwork(buses,[Branch(1,1,2;resistance=.1,reactance=.2,charging=.2,
        thermal_limit=10.,tap_ratio=2.,phase_shift=pi/2)])
    voltage=[2im,.9+.1im]
    s=ACState(abs.(voltage),angle.(voltage),Float64[],Float64[])
    flows=branch_flows(net,s)
    @test flows.from[1] ≈ -.2+.5im atol=1e-12
    @test flows.to[1] ≈ .24-.602im atol=1e-12
    @test DroopOPF._admittance_matrix(net)*voltage ≈ [.25-.1im,.19+.69im] atol=1e-12
    @test real(flows.from[1]+flows.to[1]) ≈ .04 atol=1e-12
    @test power_balance(net,s,Generator[],Load[]).vector ≈ [.2,-.24,-.5,.602] atol=1e-12
    for phi in (-.2,0.,.2)
        ratio=1.1
        n=ACNetwork(buses,[Branch(1,1,2;resistance=0.,reactance=.1,thermal_limit=10.,tap_ratio=ratio,phase_shift=phi)])
        f=branch_flows(n,state)
        @test real(f.from[1]) ≈ -10sin(phi)/ratio atol=1e-12
        @test real(f.to[1]) ≈ 10sin(phi)/ratio atol=1e-12
        @test imag(f.from[1]) ≈ 10/ratio^2-10cos(phi)/ratio atol=1e-12
        @test imag(f.to[1]) ≈ 10-10cos(phi)/ratio atol=1e-12
    end
    off=ACNetwork(buses,[Branch(1,1,2;resistance=.1,reactance=.2,charging=.2,
        thermal_limit=10.,tap_ratio=2.,phase_shift=pi/2,available=false)])
    @test branch_flows(off,s).from == branch_flows(off,s).to == [0im]
    @test iszero(DroopOPF._admittance_matrix(off))
    # Each terminal must independently enforce the rating; the larger end changes with ratio.
    for (ratio,rating,limiting) in ((1.1,.87,:to),(.9,1.17,:from))
        n=ACNetwork(buses,[Branch(1,1,2;resistance=0.,reactance=.1,thermal_limit=rating,tap_ratio=ratio)])
        f=branch_flows(n,state)
        @test abs(getproperty(f,limiting)[1]) > rating
        other=limiting == :to ? :from : :to
        @test abs(getproperty(f,other)[1]) < rating
        @test operating_margins(n,state)[1] < 0
        model=Model(Ipopt.Optimizer); set_silent(model)
        @variable(model,vm[1:2]); @variable(model,va[1:2])
        for i in 1:2
            fix(vm[i],1.;force=true); fix(va[i],0.;force=true)
        end
        DroopOPF._add_branch_thermal_limits!(model,n,vm,va)
        optimize!(model)
        @test termination_status(model) in (MOI.INFEASIBLE,MOI.LOCALLY_INFEASIBLE)
    end
end

@testset "M5.4 transformer OPF, SCOPF and droop design" begin
    case=m5_transformer_case()
    results=[solve_opf(case;smooth_epsilon=1e-5,initial_state=m5_initial_state(case)),
             solve_opf(case;smooth_epsilon=1e-5,optimizer_factory=MadNLP.Optimizer,initial_state=m5_initial_state(case)),
             solve_opf_complementarity(case;initial_state=m5_initial_state(case),optimizer_attributes=m5_ccopt_options())]
    for result in results
        @test result.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED)
        @test result.state !== nothing
        @test validate_equilibrium(case,result;droop_tolerance=1e-5).valid
    end
    @test results[1].objective ≈ results[2].objective atol=1e-7
    @test results[1].objective ≈ results[3].objective atol=1e-5
    # The same solved state must fail after tap/phase corruption; it is not re-solved.
    for bad in (m5_transformer_case(tap=1.),m5_transformer_case(phase=-.02))
        @test !validate_equilibrium(bad,results[1].state).valid
        @test validate_equilibrium(bad,results[1].state).power_balance_max > 1e-3
    end
    study=m5_transformer_study()
    reference=solve_scopf(study;smooth_epsilon=1e-5,initial_states=m5_initial_states(study))
    @test equilibrium_report(study,reference).valid
    for result in (solve_scopf(study;smooth_epsilon=1e-5,optimizer_factory=MadNLP.Optimizer,initial_states=reference.states),
                   solve_scopf(study;encoding=:complementarity,initial_states=reference.states,optimizer_attributes=m5_ccopt_options()))
        @test equilibrium_report(study,result).valid
        @test result.objective ≈ reference.objective atol=1e-5
    end
    corrective=m5_transformer_study(mode=:corrective)
    @test equilibrium_report(corrective,solve_scopf(corrective;smooth_epsilon=1e-5,initial_states=m5_initial_states(corrective))).valid
    overlay=scenario_case(case,study.contingencies[1])
    flows=branch_flows(overlay.network,reference.states[:transformer_out])
    @test flows.from[1] == flows.to[1] == 0
    @test case.network.branches[1].available
    design=optimize_droop_parameters(study,2;slope_bounds=(.04,.10),
        smooth_epsilon=1e-5,reference_result=reference)
    @test validate_droop_design(study,design).valid
    @test with_droop_settings(study,design).case.network.branches == case.network.branches
    mktempdir() do dir
        path=joinpath(dir,"study.json"); write_study(path,study)
        @test equilibrium_report(read_study(path),reference).valid
    end
end
