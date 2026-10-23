using JSON

function feasibility_test_case(;p=.5,q=0.,droop=false,vmin=.9,vmax=1.1)
    g=Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,initial_p=.5)
    d=VoltVarDroop(VoltageSchedule(1.),.02,0.,ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.))
    Case("feasibility-test";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;v_min=vmin,v_max=vmax,reference=true)],Branch[]),
        generators=[g],loads=[Load(1,1;p,q)],controls=droop ? [d] : VoltVarDroop[],
        attachments=droop ? [GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))] : GeneratorControlAttachment[])
end
function feasibility_fake_result(state,status=:LOCALLY_INFEASIBLE;taps=Dict{Int,Float64}(),shunts=Dict{Int,Float64}())
    opf=ACOPFResult{Float64}(state,NaN,status,:UNKNOWN_RESULT_STATUS,nothing,nothing,nothing)
    JointDesignResult(opf,taps,shunts,Dict{Int,DroopSettings{Float64}}(),TapControl[],ShuntControl[],DroopControl[])
end

@testset "Feasibility gate evidence and scope" begin
    c=feasibility_test_case(droop=true);p=FeasibilityProblem(c)
    s=ACState([1.],[0.],[.5],[0.]);w=FeasibilityWitness(s)
    r=check_feasibility(p;witnesses=[w],solve_missing=false)
    @test r.status==:feasible
    @test verify_feasibility_result(p,r)
    @test r.certificate===nothing
    @test feasibility_fingerprint(p)==feasibility_fingerprint(FeasibilityProblem(deepcopy(c)))
    @test feasibility_fingerprint(p)!=feasibility_fingerprint(FeasibilityProblem(c;droop_tolerance=1e-6))
    @test feasibility_fingerprint(p)!=feasibility_fingerprint(FeasibilityProblem(feasibility_test_case(p=.45,droop=true)))
    @test !verify_feasibility_result(FeasibilityProblem(feasibility_test_case()),r)
    # A returned point is sufficient even when the optimizer did not converge.
    found=check_feasibility(p;_search=(_,s)->feasibility_fake_result(w.state,:ITERATION_LIMIT))
    @test found.status==:feasible
    @test found.attempts[end]["termination_status"]=="ITERATION_LIMIT"
    # Conversely an optimal or infeasible status alone is never evidence.
    for status in (:LOCALLY_INFEASIBLE,:INFEASIBLE,:OPTIMAL,:TIME_LIMIT)
        failed=check_feasibility(p;_search=(_,s)->feasibility_fake_result(nothing,status))
        @test failed.status==:unresolved
        @test verify_feasibility_result(p,failed)
    end
    bad=FeasibilityWitness(ACState([1.],[0.],[.6],[0.]))
    @test !validate_feasibility_witness(p,bad)["valid"]
    bad.state.vm[1]=NaN
    @test !validate_feasibility_witness(p,bad)["valid"]
    @test !validate_feasibility_witness(p,FeasibilityWitness(ACState([1.,1.],[0.,0.],[.5],[0.])))["valid"]
    @test !validate_feasibility_witness(p,FeasibilityWitness(ACState([1.],[.1],[.5],[0.])))["valid"]
    # Later mutation of caller-owned input cannot modify a problem snapshot.
    c.loads[1]=Load(1,1;p=.9,q=0.)
    @test verify_feasibility_result(p,r)
    mutated=deepcopy(p);mutated.case.loads[1]=Load(1,1;p=.9,q=0.)
    @test_throws ArgumentError feasibility_fingerprint(mutated)
    mutated=deepcopy(p);mutated.case.controls[1].curve.values[1]=99.
    @test_throws ArgumentError feasibility_fingerprint(mutated)
    forged=deepcopy(r);forged.witness.state.pg[1]=.7
    @test !verify_feasibility_result(p,forged)
    @test_throws ArgumentError write_feasibility_result(tempname(),p,forged)
    mktempdir() do dir
        path=write_feasibility_result(joinpath(dir,"gate.json"),p,r)
        data=JSON.parsefile(path)["data"]
        @test data["result"]["status"]=="feasible"
        @test data["problem"]["exact_droop_curves"][1]["breakpoints"]==droop_curve(p.case.controls[1]).breakpoints
        loaded=read_feasibility_result(path,p)
        @test loaded.status==:feasible
        @test verify_feasibility_result(p,loaded)
        @test_throws ArgumentError read_feasibility_result(path,FeasibilityProblem(c))
        stored=JSON.parsefile(path)
        stored["data"]["result"]["witness"]["state"]["pg"][1]=.6
        write(path,JSON.json(stored))
        @test_throws ArgumentError read_feasibility_result(path,p)
    end
end

@testset "Exact global necessary-condition certificates" begin
    p=FeasibilityProblem(feasibility_test_case(p=1.1))
    r=check_feasibility(p;solve_missing=false)
    @test r.status==:certified_infeasible
    @test r.certificate["method"]=="island_active_capacity"
    @test verify_feasibility_result(p,r)
    mktempdir() do dir
        path=write_feasibility_result(joinpath(dir,"certificate.json"),p,r)
        @test read_feasibility_result(path,p).status==:certified_infeasible
    end
    changed=deepcopy(r);changed.certificate["strict_gap_exact"]="1//2"
    @test !verify_feasibility_result(p,changed)
    # Within declared tolerances there must be no spurious certificate.
    near=FeasibilityProblem(feasibility_test_case(p=1.0+1e-6))
    @test check_feasibility(near;solve_missing=false).status==:unresolved
    # No line can carry away positive droop Q at a zero-Q isolated load.
    p=FeasibilityProblem(feasibility_test_case(droop=true,vmin=.98,vmax=.99))
    r=check_feasibility(p;solve_missing=false)
    @test r.status==:certified_infeasible
    @test r.certificate["method"]=="bus_reactive_export"
    @test verify_feasibility_result(p,r)
    p=FeasibilityProblem(feasibility_test_case(droop=true,vmin=1.01,vmax=1.02))
    @test check_feasibility(p;solve_missing=false).certificate["method"]=="bus_reactive_import"
    # A disconnected load must not borrow capacity from another island.
    c=feasibility_test_case()
    island=Case("islands";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true),Bus(2)],Branch[]),generators=c.generators,
        loads=[Load(1,2;p=.1,q=0.)],controls=c.controls,attachments=c.attachments)
    @test check_feasibility(FeasibilityProblem(island);solve_missing=false).certificate["ids"]==[2]
end

@testset "Equipment and branch angle scope cannot leak" begin
    g=Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.)
    net=ACNetwork([Bus(1;reference=true),Bus(2)],
        [Branch(1,1,2;resistance=.01,reactance=.1,thermal_limit=2.,kind=:transformer)],
        banks=[ShuntBank(1,2;step_susceptances=(.1,),legal_states=((0,),(1,)),state=(0,))])
    c=Case("equipment-gate";base_power=100.,base_frequency=50.,network=net,generators=[g],
        controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    fixed=FeasibilityProblem(c)
    free=FeasibilityProblem(c;tap_controls=[TapControl(1;lower=.9,upper=1.1)],shunt_controls=[ShuntControl(1)])
    @test feasibility_fingerprint(fixed)!=feasibility_fingerprint(free)
    w=FeasibilityWitness(ACState([1.05,1.],[0.,0.],[0.],[0.]);taps=Dict(1=>1.05))
    @test validate_feasibility_witness(free,w)["valid"]
    @test !validate_feasibility_witness(fixed,w)["valid"]
    r=check_feasibility(free;witnesses=[w],solve_missing=false)
    @test !verify_feasibility_result(fixed,r)
    # Even a zero setting for an unselected bank must be explicitly scoped.
    @test !validate_feasibility_witness(fixed,FeasibilityWitness(w.state;susceptances=Dict(1=>0.)))["valid"]
    bad=FeasibilityWitness(w.state;taps=Dict(1=>1.2))
    @test !validate_feasibility_witness(free,bad)["valid"]
    # This equilibrium has nonzero phase difference with zero branch flow.
    branch=Branch(1,1,2;resistance=.01,reactance=.1,thermal_limit=2.,phase_shift=.1)
    shifted=Case("phase";base_power=100.,base_frequency=50.,network=ACNetwork(net.buses,[branch]),
        generators=[g],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    w=FeasibilityWitness(ACState([1.,1.],[0.,-.1],[0.],[0.]))
    @test validate_feasibility_witness(FeasibilityProblem(shifted),w)["valid"]
    p=FeasibilityProblem(shifted;angle_limits=Dict(1=>(-.05,.05)))
    @test !validate_feasibility_witness(p,w)["valid"]
    @test_throws ArgumentError FeasibilityProblem(c;angle_limits=Dict(99=>(-1.,1.)))
end

@testset "Droop replacement precursor and actual local search" begin
    c=feasibility_test_case();candidate=feasibility_test_case(droop=true)
    source=ACState([1.],[0.],[.5],[0.]);low=ACState([1.],[0.],[.45],[0.])
    witnesses=Dict("source/0.9"=>[FeasibilityWitness(low)],"candidate/0.9"=>[FeasibilityWitness(low)])
    q=qualify_droop_replacement(c,candidate;calibration_state=source,witnesses,
        search_options=(solve_missing=false,))
    @test length(q.results)==6
    @test all(r.status==:feasible for r in q.results)
    @test length(require_qualified_replacement(q).controls)==1
    mktempdir() do dir
        path=write_droop_qualification(joinpath(dir,"qualification.json"),q)
        @test JSON.parsefile(path)["data"]["accepted"]
    end
    qbad=qualify_droop_replacement(c,candidate;calibration_state=source,search_options=(solve_missing=false,))
    @test_throws ArgumentError require_qualified_replacement(qbad)
    @test_throws ArgumentError qualify_droop_replacement(c,feasibility_test_case(p=.6,droop=true);calibration_state=source)
    @test_throws ArgumentError qualify_droop_replacement(c,candidate;calibration_state=source,load_factors=())
    # Solver search cannot rescue a miscalibrated source point.
    miscalibrated=ACState([1.01],[0.],[.5],[0.])
    qbad=qualify_droop_replacement(c,candidate;calibration_state=miscalibrated,load_factors=(1.,),
        witnesses=Dict("candidate/1.0"=>[FeasibilityWitness(source)]),search_options=(solve_missing=false,))
    @test qbad.results[2].status!=:feasible
    @test_throws ArgumentError require_qualified_replacement(qbad)
    # Exercise the actual JuMP/Ipopt constant-objective search once.
    r=check_feasibility(FeasibilityProblem(candidate);initial_states=[ACState([1.01],[0.],[.3],[.1])])
    @test r.status==:feasible
    @test verify_feasibility_result(FeasibilityProblem(candidate),r)
end
