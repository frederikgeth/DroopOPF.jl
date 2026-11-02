@testset "Backend-neutral imported-state validation" begin
    c = Case("flat";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true),Bus(2)],
            [Branch(1,1,2;resistance=.01,reactance=.1,thermal_limit=1.)]),
        generators=[Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,initial_p=0.,initial_q=0.)],
        loads=Load[],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    s = ACState([1.,1.],[0.,0.],[0.],[0.])
    md = CaseIOMetadata()
    for key in (:VM,:VA); md.saved_field_presence[key] = fill(:supplied,2); end
    for key in (:PG,:QG); md.saved_field_presence[key] = [:supplied]; end
    md.branch_rating_mva[1] = 100.
    source = CaseSource(:native,:matpower,nothing,"fixture.m","digest","test",nothing)
    snapshot() = CaseImport(c,s,DroopOPF._io_identities(),md,CaseIODiagnostic[],source)
    r = snapshot()
    report = validate_imported_state(r)
    @test report["valid"]
    @test report["power_flow_consistent"]
    @test report["saved_state_complete"]
    @test report["thermal_coverage_complete"]
    @test !report["optimization_performed"]
    md.saved_field_presence[:VM] = [:unknown,:unknown]
    @test_throws CaseIOError validate_imported_state(r)
    r = snapshot()
    report = validate_imported_state(r)
    @test report["power_flow_consistent"]
    @test !report["saved_state_complete"]
    @test !report["valid"]
    @test length(report["missing_saved_fields"]) == 2
    md.saved_field_presence[:VM] = [:supplied,:supplied]
    md.branch_rating_mva[1] = nothing
    r = snapshot()
    report = validate_imported_state(r)
    @test report["known_limits_valid"]
    @test !report["thermal_coverage_complete"]
    @test !report["valid"]
    @test report["status"] == "limits_unassessed"
    @test only(report["branch_flows"])["normal_rating_mva"] === nothing
    @test report["unrated_branches"] == [1]
    bad = CaseImport(c,ACState([1.,1.],[0.,0.],[.2],[0.]),r.source_ids,md,r.diagnostics,source)
    @test !validate_imported_state(bad)["power_flow_consistent"]
    @test_throws ArgumentError validate_imported_state(r;power_tolerance_mw=NaN)
    r.initial_state.vm[1] = 1.01
    @test_throws CaseIOError validate_imported_state(r)
    r.initial_state.vm[1] = 1.
    md.saved_field_presence[:VM] = [:supplied]
    @test_throws CaseIOError validate_imported_state(r)
    # Legacy RAW report remains an independent compatibility reference.
    path = joinpath(@__DIR__,"..","data","psse","synthetic_v33.raw")
    common = validate_imported_state(import_case(path))
    legacy = validate_psse_saved_solution(import_psse_case(parse_psse_raw(path)))
    for key in ("valid","saved_state_complete","known_limits_valid","thermal_coverage_complete",
        "max_p_mismatch_mw","max_q_mismatch_mvar","limit_violations")
        @test common[key] == legacy[key]
    end
end
