function global_test_case(;phase=.1)
    g1=Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.)
    g2=Generator(2,2;p_min=0.,p_max=1.,q_min=-1.,q_max=1.)
    droop=VoltVarDroop(VoltageSchedule(1.05),.02,0.,ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.))
    net=ACNetwork([Bus(1;reference=true),Bus(2)],
        [Branch(1,1,2;resistance=.01,reactance=.1,thermal_limit=1.,tap_ratio=1.05,phase_shift=phase)],
        shunts=[FixedShunt(1,2;conductance=.02,susceptance=.05)],
        banks=[ShuntBank(2,2;step_susceptances=(.05,),legal_states=((0,),(1,)),state=(1,))])
    c=Case("global-seed";base_power=100.,base_frequency=50.,network=net,generators=[g1,g2],
        controls=[droop],attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
    c,ACState([1.05,1.],[0.,-phase],[0.,.02],[0.,-.1])
end

@testset "Sparse global model and exact rational outer relaxation" begin
    c,s=global_test_case();p=FeasibilityProblem(c;angle_limits=Dict(1=>(-.2,.2)))
    @test validate_feasibility_witness(p,FeasibilityWitness(s))["valid"]
    for mode in (:soc,:global)
        built=build_global_feasibility_model(p;target_bus=2,mode)
        @test seed_global_feasibility!(built,s).max_violation==0.
        @test built.metadata["active_edges"]==1
        @test isempty(built.metadata["omitted_angle_windows"])
        @test length(built.variables.curves[1].lambda)>=2
    end
    @test_throws ArgumentError build_global_feasibility_model(p;target_bus=99)
    @test_throws ArgumentError build_global_feasibility_model(p;target_bus=2,max_relaxation=-1.)
    @test_throws ArgumentError build_global_feasibility_model(p;target_bus=2,mode=:bad)
    @test Generator(3,1;available=false,p_min=0.,p_max=1.,q_min=0.,q_max=0.).q_max==0.
    @test Generator(3,1;available=true,p_min=0.,p_max=1.,q_min=0.,q_max=0.).q_max==0.
    @test_throws ArgumentError Generator(3,1;p_min=0.,p_max=1.,q_min=.1,q_max=0.)
    free=FeasibilityProblem(c;tap_controls=[TapControl(1;lower=.9,upper=1.1)])
    @test_throws ArgumentError build_global_feasibility_model(free;target_bus=2)
    @test_throws ArgumentError DroopOPF._feasibility_lp(p)
    c,s=global_test_case(phase=0.);p=FeasibilityProblem(c)
    d=DroopOPF._feasibility_lp(p)
    @test length(d.edges)==1
    @test all(lo<=hi for (lo,hi) in d.bounds)
    # Support cuts must be valid regardless of their generating point.
    @test_throws ArgumentError DroopOPF._flp_cut!(d,Dict("kind"=>"edge","index"=>1,"direction"=>["2//1","0//1","0//1"]))
    @test_throws ArgumentError DroopOPF._flp_cut!(d,Dict("kind"=>"thermal","index"=>1,"direction"=>["1//1","1//1"]))
    @test_throws ArgumentError DroopOPF._flp_cut!(d,Dict("kind"=>"arbitrary","index"=>1))
    for vec in ([1.,2.,3.],[-1.,0.],[1e-6,2e-6])
        dir=DroopOPF._flp_parse.(DroopOPF._flp_direction(vec))
        @test sum(abs2,dir)<=1
    end
    # Explicitly inspect a one-variable Farkas contradiction, including
    # stationarity residuals over the variable box.
    toy=DroopOPF._FeasibilityLP([(big(0)//1,big(1)//1)],
        [(Dict(1=>-big(1)//1),-big(2)//1)],Int[],Int[],Int[],Int[],Tuple{Int,Int}[],
        Tuple{Dict{Int,Rational{BigInt}},Dict{Int,Rational{BigInt}},Rational{BigInt}}[])
    @test DroopOPF._flp_margin(toy,[[1,"1//1"]])==1
    @test_throws ArgumentError DroopOPF._flp_margin(toy,[[1,"-1//1"]])
end

@testset "Cycle PSD cuts with exact rational replay" begin
    buses=[Bus(i;reference=i==1) for i in 1:4]
    branches=[Branch(k,i,j;resistance=.01,reactance=.1,thermal_limit=10.)
        for (k,(i,j)) in enumerate([(1,2),(2,3),(3,4),(4,1)])]
    c=Case("cycle-cut-check";base_power=100.,base_frequency=50.,network=ACNetwork(buses,branches),
        generators=Generator[],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    p=FeasibilityProblem(c);d=DroopOPF._feasibility_lp(p;psd_clique_limit=3)
    @test length(d.edges)==5 # one shared fill product triangulates the four-cycle
    @test length(d.cliques)==2
    @test all(length(cl)==3 for cl in d.cliques)
    @test_throws ArgumentError DroopOPF._feasibility_lp(p;psd_clique_limit=2)
    x=zeros(length(d.bounds));x[d.w].=1.;x[d.v].=1.;x[d.wr].=-1.
    # Every edge is SOC-feasible, but each triangle with off-diagonal -1 is not PSD.
    cuts=DroopOPF._flp_psd_cuts(d,x)
    @test !isempty(cuts)
    for cut in cuts
        row=DroopOPF._flp_psd_row(d,cut)
        @test sum(Float64(v)*x[i] for (i,v) in row)>1e-4
        # Verify sign/conjugation against physical rank-one products with a wide
        # range of magnitudes and phases, including the reversed fourth branch.
        for trial in 1:20
            voltage=[(.9+.01*mod(i+trial,20))*cis(.31*i*trial) for i in 1:4]
            point=zeros(length(d.bounds));point[d.w]=abs2.(voltage)
            for (k,(i,j)) in enumerate(d.edges)
                value=voltage[i]*conj(voltage[j]);point[d.wr[k]]=real(value);point[d.wi[k]]=imag(value)
            end
            @test sum(Float64(v)*point[i] for (i,v) in row)<=1e-10
        end
    end
    cut=Dict("kind"=>"psd","nodes"=>d.cliques[1],"real"=>fill("1//1",3),"imag"=>fill("0//1",3))
    DroopOPF._flp_cut!(d,cut)
    # Fix the deliberately inconsistent lifted point. The PSD row alone gives
    # an exact positive contradiction, with no reliance on numerical eigenvalues.
    d.bounds=[(DroopOPF._fq(v),DroopOPF._fq(v)) for v in x]
    @test DroopOPF._flp_margin(d,[[length(d.rows),"1//1"]])==3
    bad=deepcopy(cut);bad["nodes"]=[1,2,99]
    @test_throws ArgumentError DroopOPF._flp_cut!(d,bad)
    bad=deepcopy(cut);bad["imag"]=["0//1"]
    @test_throws ArgumentError DroopOPF._flp_cut!(d,bad)
end
