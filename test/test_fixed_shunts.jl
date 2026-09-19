using JSON

@testset "M6.1 fixed shunt data and migration" begin
    for (g,b) in ((-1.,0.),(Inf,0.),(NaN,0.),(0.,Inf),(0.,NaN))
        @test_throws ArgumentError FixedShunt(1,10;conductance=g,susceptance=b)
    end
    @test_throws ArgumentError FixedShunt(0,10;susceptance=.1)
    @test_throws ArgumentError FixedShunt(1,0;susceptance=.1)
    s=FixedShunt(8,10;conductance=.02,susceptance=.1)
    @test_throws ArgumentError ACNetwork([Bus(10)],Branch[];shunts=[s,s])
    @test_throws ArgumentError ACNetwork([Bus(20)],Branch[];shunts=[s])
    @test isempty(ACNetwork([Bus(10)],Branch[]).shunts)
    @test isempty(ACNetwork{Float64}([Bus(10)],Branch{Float64}[]).shunts)
    net=ACNetwork([Bus(10)],Branch[];shunts=[FixedShunt(8,10;conductance=big"0.02",susceptance=big"0.1")])
    @test net isa ACNetwork{BigFloat}
    @test net.shunts[1].susceptance == big"0.1"
    path=joinpath(@__DIR__,"data","shunt3.m")
    c=load_matpower_case(path)
    @test [s.id for s in c.network.shunts] == [1,3]
    @test c.network.shunts[1].conductance == .02
    @test c.network.shunts[1].susceptance == .1
    @test c.network.shunts[2].susceptance == -.05
    plain=load_matpower_case(joinpath(@__DIR__,"data","case3.m"))
    @test c.loads == plain.loads
    @test c.network.branches == plain.network.branches
    @test attach_controls(c,c.controls,c.attachments).network.shunts == c.network.shunts
    overlay=scenario_case(c,Contingency(:branch_out;branch_ids=[1]))
    @test overlay.network.shunts == c.network.shunts
    @test overlay.network.shunts !== c.network.shunts
    promoted=Case("promoted";base_power=big"100",base_frequency=50,network=c.network,
        loads=c.loads,generators=c.generators,controls=c.controls,attachments=c.attachments)
    @test promoted.network.shunts[1].conductance == BigFloat(.02)
    @test promoted.network.shunts[1].susceptance == BigFloat(.1)
    state=ACState(ones(3),zeros(3),[.8,.4],[.1,.4])
    @test branch_flows(c.network,state) == branch_flows(plain.network,state)
    difference=power_balance(c,state).vector-power_balance(plain,state).vector
    @test difference ≈ [-.02,0.,0.,.1,0.,-.05] atol=1e-14
    mktempdir() do dir
        path=joinpath(dir,"study.json"); write_study(path,Study(c))
        @test read_study(path).case.network.shunts == c.network.shunts
        doc=JSON.parsefile(path)
        @test doc["schema_version"] == 4
        delete!(doc["data"]["case"]["network"],"shunts")
        write(path,JSON.json(doc)); @test_throws ArgumentError read_study(path)
        for version in (1,2)
            write_study(path,Study(c)); doc=JSON.parsefile(path); doc["schema_version"]=version
            write(path,JSON.json(doc)); @test_throws ArgumentError read_study(path)
            delete!(doc["data"]["case"]["network"],"shunts")
            if version==1
                for b in doc["data"]["case"]["network"]["branches"]
                    delete!(b,"tap_ratio"); delete!(b,"phase_shift")
                end
            end
            write(path,JSON.json(doc)); @test isempty(read_study(path).case.network.shunts)
        end
    end
end

@testset "M6.1 analytical V-squared physics" begin
    buses=[Bus(10;reference=true,v_min=.8,v_max=1.2)]
    gen=Generator(7,10;p_min=0.,p_max=2.,q_min=-1.,q_max=1.,initial_p=.5,initial_q=.1)
    load=Load(3,10;p=.5,q=.3)
    makecase(shunts)=Case("m61-analytical";base_power=100.,base_frequency=50.,
        network=ACNetwork(buses,Branch[];shunts=shunts),loads=[load],generators=[gen],
        controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    for b in (-.2,0.,.2), v in (.9,1.,1.1)
        shunt=FixedShunt(8,10;conductance=.04,susceptance=b)
        c=makecase([shunt])
        state=ACState([v],[0.],[.5+.04*v^2],[.3-b*v^2])
        expected=complex(.04*v^2,-b*v^2)
        @test only(shunt_powers(c.network,state)) ≈ expected atol=1e-14
        @test only(DroopOPF._admittance_matrix(c.network)) ≈ .04+b*im atol=1e-14
        @test validate_equilibrium(c,state).valid
        @test !validate_equilibrium(makecase(FixedShunt[]),state).valid
        doubled=makecase([shunt,FixedShunt(9,10;conductance=.04,susceptance=b)])
        @test !validate_equilibrium(doubled,state).valid
        if b != 0
            wrong=makecase([FixedShunt(8,10;conductance=.04,susceptance=-b)])
            @test !validate_equilibrium(wrong,state).valid
        end
        unavailable=makecase([FixedShunt(8,10;conductance=.04,susceptance=b,available=false)])
        @test only(shunt_powers(unavailable.network,state)) == 0im
        @test iszero(DroopOPF._admittance_matrix(unavailable.network))
        @test validate_equilibrium(unavailable,ACState([v],[0.],[.5],[.3])).valid
        # A fixed admittance is invariant to voltage angle, but not magnitude.
        @test shunt_powers(c.network,ACState([v],[.7],state.pg,state.qg)) ≈ [expected] atol=1e-14
    end
    # Multiple equipment records at a bus sum once; branch charging is separate.
    net=ACNetwork([Bus(10),Bus(20)],[Branch(1,10,20;resistance=0.,reactance=.1,
        charging=.2,thermal_limit=5.)];shunts=[FixedShunt(1,10;susceptance=.1),FixedShunt(2,10;susceptance=.05)])
    state=ACState(ones(2),zeros(2),Float64[],Float64[])
    @test shunt_powers(net,state) ≈ [-.1im,-.05im]
    @test branch_flows(net,state).from ≈ [-.1im]
    @test power_balance(net,state,Generator[],Load[]).reactive ≈ [.25,.1] atol=1e-14
    @test_throws ArgumentError shunt_powers(net,ACState([1.],[0.],Float64[],Float64[]))
    # A one-bus shunt study has a valid empty branch vector on JSON reload.
    mktempdir() do dir
        c=makecase([FixedShunt(8,10;conductance=.04,susceptance=.2,available=false)])
        path=joinpath(dir,"onebus.json"); write_study(path,Study(c))
        restored=read_study(path).case
        @test isempty(restored.network.branches)
        @test restored.network.shunts == c.network.shunts
    end
    # Basic OPF safety check for the shared fixed-admittance Ybus path.
    c=makecase([FixedShunt(8,10;conductance=.04,susceptance=.2)])
    result=solve_opf(c)
    @test result.termination_status == :LOCALLY_SOLVED
    @test validate_equilibrium(c,result).valid
end
