using JSON, MadNLP
include(joinpath(@__DIR__,"..","examples","m6_shunt_case.jl"))

@testset "M6.2 supplied bank states" begin
    bank=m6_bank()
    @test bank_admittance(bank) == .001+.02im
    @test bank.state == bank.nominal_state == (1,0)
    @test with_bank_state(bank,(2,0)).nominal_state == (1,0)
    for state in ((3,0),(-1,0),(1.,0.),(1,))
        @test_throws ArgumentError with_bank_state(bank,state)
    end
    @test_throws ArgumentError with_bank_state(bank,(3,0);available=false)
    for kwargs in ((step_conductances=(-1.,),step_susceptances=(.1,)),
                   (step_conductances=(NaN,),step_susceptances=(.1,)),
                   (step_conductances=(0.,),step_susceptances=(Inf,)),
                   (step_conductances=(),step_susceptances=()),
                   (step_conductances=(0.,0.),step_susceptances=(.1,)))
        @test_throws ArgumentError ShuntBank(1,10;kwargs...,legal_states=((0,),(1,)),state=(0,))
    end
    @test_throws ArgumentError ShuntBank(1,10;step_susceptances=(.1,),legal_states=((0,),(0,)),state=(0,))
    @test_throws ArgumentError ShuntBank(1,10;step_susceptances=(.1,),legal_states=(),state=(0,))
    @test_throws ArgumentError ShuntBank(1,10;step_susceptances=(.1,),legal_states=((0,),),state=(0,),nominal_state=(1,))
    bs=[.1]; legal=[[0],[1]]; state=[1]
    copied=ShuntBank(8,10;step_susceptances=bs,legal_states=legal,state=state)
    bs[1]=9.; legal[2][1]=9; state[1]=0
    @test copied.step_susceptances == (.1,)
    @test copied.legal_states == ((0,),(1,))
    @test copied.state == (1,)
    buses=[Bus(30;reference=true)]
    @test_throws ArgumentError ACNetwork(buses,Branch[];banks=[bank,bank])
    @test_throws ArgumentError ACNetwork([Bus(10)],Branch[];banks=[bank])
    @test_throws ArgumentError ACNetwork(buses,Branch[];banks=[bank],shunts=[FixedShunt(201,30;susceptance=.1)])
    @test isempty(ACNetwork(buses,Branch[]).banks)
    @test isempty(ACNetwork{Float64}(buses,Branch{Float64}[]).banks)
    for state in bank.legal_states, v in (.9,1.,1.1)
        b=with_bank_state(bank,state)
        net=ACNetwork(buses,Branch[];banks=[b],shunts=[FixedShunt(101,30;conductance=.002,susceptance=.01)])
        ac=ACState([v],[.3],Float64[],Float64[])
        g=.001*state[1]+.0005*state[2]; susceptance=.02*state[1]-.01*state[2]
        @test bank_admittance(b) ≈ complex(g,susceptance) atol=1e-15
        @test only(bank_powers(net,ac)) ≈ complex(g,-susceptance)*v^2 atol=1e-15
        @test only(DroopOPF._admittance_matrix(net)) ≈ complex(g+.002,susceptance+.01)
        @test power_balance(net,ac,Generator[],Load[]).vector ≈ [-(g+.002)*v^2,(susceptance+.01)*v^2] atol=1e-15
    end
    off=with_bank_state(bank,(2,0);available=false)
    net=ACNetwork(buses,Branch[];banks=[off])
    @test bank_admittance(off) == 0im
    @test only(bank_powers(net,ACState([1.],[0.],Float64[],Float64[]))) == 0im
    @test iszero(DroopOPF._admittance_matrix(net))
    @test off.state == (2,0)
    c=m6_shunt_case()
    @test attach_controls(c,c.controls,c.attachments).network.banks == c.network.banks
    @test scenario_case(c,Contingency(:out;branch_ids=[11])).network.banks == c.network.banks
    promoted=Case("promoted";base_power=big"100",base_frequency=50.,network=c.network,
        loads=c.loads,generators=c.generators,controls=c.controls,attachments=c.attachments)
    @test promoted.network.banks[1] isa ShuntBank{BigFloat}
    @test first(promoted.network.banks[1].step_susceptances) == BigFloat(.02)
    mktempdir() do dir
        path=joinpath(dir,"study.json"); write_study(path,m6_shunt_study())
        @test read_study(path).case.network.banks == c.network.banks
        doc=JSON.parsefile(path); @test doc["schema_version"] == 4
        delete!(doc["data"]["case"]["network"],"banks")
        write(path,JSON.json(doc)); @test_throws ArgumentError read_study(path)
        for version in (1,2,3)
            write_study(path,m6_shunt_study()); doc=JSON.parsefile(path); doc["schema_version"]=version
            write(path,JSON.json(doc)); @test_throws ArgumentError read_study(path)
            n=doc["data"]["case"]["network"]; delete!(n,"banks")
            version<3 && delete!(n,"shunts")
            if version==1
                for br in n["branches"]
                    delete!(br,"tap_ratio"); delete!(br,"phase_shift")
                end
            end
            write(path,JSON.json(doc)); @test isempty(read_study(path).case.network.banks)
        end
    end
end

@testset "M6.3 fixed-state OPF/SCOPF integration" begin
    c=m6_shunt_case()
    base=solve_opf(c;smooth_epsilon=1e-5,initial_state=m5_initial_state(c))
    @test validate_equilibrium(c,base).valid
    study=m6_shunt_study()
    ref=solve_scopf(study;smooth_epsilon=1e-5,initial_states=m5_initial_states(study))
    @test equilibrium_report(study,ref).valid
    for result in (solve_scopf(study;smooth_epsilon=1e-5,optimizer_factory=MadNLP.Optimizer,initial_states=ref.states),
                   solve_scopf(study;encoding=:complementarity,initial_states=ref.states,optimizer_attributes=m5_ccopt_options()))
        @test equilibrium_report(study,result).valid
        @test result.objective ≈ ref.objective atol=1e-6
    end
    corrective=m6_shunt_study(mode=:corrective)
    @test equilibrium_report(corrective,solve_scopf(corrective;smooth_epsilon=1e-5,initial_states=m5_initial_states(corrective))).valid
    design=optimize_droop_parameters(study,2;slope_bounds=(.04,.1),reference_result=ref,smooth_epsilon=1e-5)
    @test validate_droop_design(study,design).valid
    @test with_droop_settings(study,design).case.network.banks == c.network.banks
    @test c.network.banks[1].state == (1,0)
    for bad in (m6_shunt_case(state=(0,0)),m6_shunt_case(include_bank=false),m6_shunt_case(available=false))
        @test !validate_equilibrium(bad,ref.states[:base]).valid
    end
    zero=m6_shunt_case(include_fixed=false,include_bank=false)
    original=m5_transformer_case()
    @test power_balance(zero,base.state).vector == power_balance(original,base.state).vector
    # Fixed-plus-bank conductance and independent accounting in every scenario.
    for (id,case) in zip([:base;[o.id for o in study.contingencies]],
                         [c;[scenario_case(c,o) for o in study.contingencies]])
        state=ref.states[id]
        @test real(sum(shunt_powers(case.network,state))+sum(bank_powers(case.network,state))) >= 0
        @test maximum(abs,power_balance(case,state).vector) < 1e-6
    end
end
