# Optional integration checks: activate an environment with SCIP and HiGHS.
using SCIP,HiGHS
@testset "Verified LP certificates and optional global solver" begin
    c,s=global_test_case(phase=0.);p=FeasibilityProblem(c)
    r=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit=30.)
    @test r.status==:unresolved
    @test verify_feasibility_result(p,r)
    # Aggregate capacity is sufficient, but the connecting branch cannot
    # deliver the active load. This exceeds the earlier analytic screen.
    net=ACNetwork([Bus(1;reference=true),Bus(2)],
        [Branch(1,1,2;resistance=.01,reactance=.1,thermal_limit=.1)])
    c=Case("transfer-bottleneck";base_power=100.,base_frequency=50.,network=net,
        generators=[Generator(1,1;p_min=0.,p_max=2.,q_min=-1.,q_max=1.)],
        loads=[Load(1,2;p=.5,q=0.)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    p=FeasibilityProblem(c)
    @test check_feasibility(p;solve_missing=false).status==:unresolved
    r=check_feasibility(p;solve_missing=false,lp_options=(optimizer_factory=HiGHS.Optimizer,time_limit=30.))
    @test r.status==:certified_infeasible
    @test r.certificate["method"]=="rational_sparse_outer_lp"
    @test verify_feasibility_result(p,r)
    altered=deepcopy(r);altered.certificate["strict_gap_exact"]="0//1"
    @test !verify_feasibility_result(p,altered)
    altered=deepcopy(r);push!(altered.certificate["cuts"],Dict("kind"=>"edge","index"=>1,"direction"=>["2//1","0//1","0//1"]))
    @test !verify_feasibility_result(p,altered)
    mktempdir() do dir
        path=write_feasibility_result(joinpath(dir,"proof.json"),p,r)
        @test read_feasibility_result(path,p).status==:certified_infeasible
    end
    # An infeasible global-solver status alone must not manufacture a proof.
    result=solve_global_feasibility(p;target_bus=2,optimizer_factory=SCIP.Optimizer,time_limit=5.)
    @test result.result.status==:unresolved
    @test result.ledger["solver_reported_infeasibility"]
    c,s=global_test_case(phase=0.);p=FeasibilityProblem(c)
    result=solve_global_feasibility(p;target_bus=2,optimizer_factory=SCIP.Optimizer,
        initial_state=s,time_limit=5.,optimizer_attributes=Dict("numerics/feastol"=>1e-9))
    @test result.result.status==:feasible
    @test verify_feasibility_result(p,result.result)
    free=FeasibilityProblem(c;tap_controls=[TapControl(1;lower=.9,upper=1.1)])
    unresolved=check_feasibility(free;solve_missing=false,
        lp_options=(optimizer_factory=HiGHS.Optimizer,),
        global_options=(target_bus=2,optimizer_factory=SCIP.Optimizer,))
    @test unresolved.status==:unresolved
    @test count(a->haskey(a,"error"),unresolved.attempts)==2

    # A nonconvex droop/shunt conflict whose initial convex hull is feasible.
    # At V=.9, Qdroop+9V^2=8.29; the other local minimum at V=1.02
    # is 8.3636. Demand 8.285 cannot be supplied at any allowed voltage.
    g=Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.)
    ctrl=VoltVarDroop(VoltageSchedule(1.),.02,0.,ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.))
    net=ACNetwork([Bus(1;reference=true)],Branch[];shunts=[FixedShunt(1,1;susceptance=9.)])
    c=Case("droop-shunt-proof";base_power=100.,base_frequency=50.,network=net,generators=[g],
        loads=[Load(1,1;p=.5,q=8.285)],controls=[ctrl],attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
    p=FeasibilityProblem(c)
    @test check_feasibility(p;solve_missing=false).status==:unresolved
    root=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit=30.,max_rounds=20)
    @test root.status==:unresolved
    tightened=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit=30.,max_rounds=20,bound_tightening_rounds=3)
    @test tightened.status==:certified_infeasible
    @test !isempty(tightened.certificate["bound_stages"])
    @test verify_feasibility_result(p,tightened)
    mktempdir() do dir
        path=write_feasibility_result(joinpath(dir,"tightened-proof.json"),p,tightened)
        @test read_feasibility_result(path,p).status==:certified_infeasible
    end
    bounds=verified_feasibility_voltage_bounds(p,tightened)
    display_only=deepcopy(tightened)
    display_only.attempts[1]["voltage_bounds_pu"]=[[0.,999.]]
    @test verified_feasibility_voltage_bounds(p,display_only)==bounds
    damaged=deepcopy(tightened)
    damaged.certificate["bound_stages"][1]["bounds"][1]["lower_bound_exact"]="123//1"
    @test !verify_feasibility_result(p,damaged)
    damaged=deepcopy(tightened)
    damaged.attempts[1]["verified_bound_stages"][1]["bounds"][1]["lower_bound_exact"]="123//1"
    @test_throws ArgumentError verified_feasibility_voltage_bounds(p,damaged)
    @test_throws ArgumentError build_global_feasibility_model(p;target_bus=1,voltage_bound_result=tightened)
end

@testset "Persisted cycle-relaxation certificates" begin
    net=ACNetwork([Bus(i;reference=i==1) for i in 1:3],
        [Branch(k,i,j;resistance=.01,reactance=.1,thermal_limit=.1)
         for (k,(i,j)) in enumerate([(1,2),(2,3),(3,1)])])
    c=Case("cycle-transfer-bottleneck";base_power=100.,base_frequency=50.,network=net,
        generators=[Generator(1,1;p_min=0.,p_max=2.,q_min=-1.,q_max=1.)],
        loads=[Load(1,2;p=.5,q=0.)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    p=FeasibilityProblem(c)
    r=certify_feasibility_lp(p;optimizer_factory=HiGHS.Optimizer,time_limit=30.,psd_clique_limit=8)
    @test r.status==:certified_infeasible
    @test r.certificate["psd_clique_limit"]==8
    @test only(r.attempts)["psd_cliques"]==1
    # Additional valid cuts may be unused by the contradiction. They must still
    # reconstruct correctly, and an invalid clique must invalidate the ledger.
    cut=Dict("kind"=>"psd","nodes"=>[1,2,3],"real"=>["1//1","-1//2","0//1"],
        "imag"=>["1//4","0//1","1//1"])
    push!(r.certificate["cuts"],cut)
    @test verify_feasibility_result(p,r)
    mktempdir() do dir
        path=write_feasibility_result(joinpath(dir,"cycle-proof.json"),p,r)
        @test read_feasibility_result(path,p).status==:certified_infeasible
    end
    altered=deepcopy(r);altered.certificate["cuts"][end]["nodes"]=[1,2,4]
    @test !verify_feasibility_result(p,altered)
    altered=deepcopy(r);altered.certificate["psd_clique_limit"]=0
    @test !verify_feasibility_result(p,altered)
end
