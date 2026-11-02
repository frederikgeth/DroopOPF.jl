@testset "PowerIO prepared exports" begin
    imported = import_case(joinpath(@__DIR__,"..","data","case3.m");options=ImportOptions(base_frequency=60.))
    c = imported.case
    bound = bind_export_state(imported.initial_state,export_state_context(c))
    @test_throws CaseIOError prepare_export(c;format=:matpower,context=imported)
    plan = prepare_export(c;format=:matpower,context=imported,state=bound)
    @test plan.accepted
    @test plan.writer_fidelity == "canonical"
    @test plan.fidelity == :static_ac_projection
    @test any(d->d.code==:equipment_ids_regenerated,plan.diagnostics)
    external = import_case(joinpath(@__DIR__,"..","data","case3.m");backend=PowerIOBackend(),
        options=ImportOptions(base_frequency=60.))
    external_plan = prepare_export(external.case;format=:matpower,context=external,
        state=bind_export_state(external.initial_state,export_state_context(external.case)))
    @test external_plan.accepted
    @test_throws CaseIOError prepare_export(c;backend=NativeBackend(),format=:matpower,context=imported,state=bound)
    @test_throws CaseIOError prepare_export(c;format=:psse,revision=35,context=imported,state=bound)
    mktempdir() do dir
        path = joinpath(dir,"written.m")
        @test write_export(path,plan) == path
        r = import_case(path;options=ImportOptions(base_frequency=60.))
        @test r.initial_state.vm ≈ imported.initial_state.vm atol=1e-8
        @test r.initial_state.va ≈ imported.initial_state.va atol=1e-8
        @test r.initial_state.pg ≈ imported.initial_state.pg atol=1e-8
        @test DroopOPF._admittance_matrix(r.case.network) ≈ DroopOPF._admittance_matrix(c.network) atol=1e-8
        @test_throws CaseIOError write_export(path,plan)
        @test read(path)==plan.bytes
        @test write_export(path,plan;overwrite=true)==path
        @test_throws CaseIOError write_export(imported.source.path,plan;overwrite=true)
        link = joinpath(dir,"source_alias.m")
        symlink(imported.source.path,link)
        @test_throws CaseIOError write_export(link,plan;overwrite=true)
        hard = joinpath(dir,"source_hardlink.m")
        Base.Filesystem.hardlink(imported.source.path,hard)
        @test_throws CaseIOError write_export(hard,plan;overwrite=true)
        before = read(path)
        err = try write_export(joinpath(dir,"missing","result.m"),plan); catch e; e; end
        @test err isa CaseIOError
        @test err.code == :destination_write_error
        # Removing a source after preparation must not authorize writing to its
        # original pathname. Keep the repository fixture untouched.
        local_source = joinpath(dir,"source.m")
        cp(imported.source.path,local_source)
        local_import = import_case(local_source;options=ImportOptions(base_frequency=60.))
        local_plan = prepare_export(local_import.case;format=:matpower,context=local_import,
            options=ExportOptions(state_policy=:initial_guess))
        rm(local_source)
        @test_throws CaseIOError write_export(local_source,local_plan)
        @test !ispath(local_source)
        plan.bytes[1] ⊻= 0x01
        @test_throws CaseIOError write_export(path,plan;overwrite=true)
        @test read(path)==before
        @test_throws CaseIOError prepare_export(c;format=:matpower,metadata=CaseIOMetadata(),state=bound)
    end
    # Identity/order changes must not accidentally reuse source metadata or a state.
    reversed = Case(c.id;base_power=c.base_power,base_frequency=c.base_frequency,
        network=ACNetwork(reverse(c.network.buses),c.network.branches;shunts=c.network.shunts),
        generators=c.generators,loads=c.loads,controls=c.controls,attachments=c.attachments)
    @test_throws CaseIOError prepare_export(reversed;format=:matpower,context=imported,state=bound)
    @test_throws CaseIOError prepare_export(reversed;format=:matpower,metadata=imported.metadata,state=bound)
    @test_throws CaseIOError bind_export_state(ACState([1.],[0.],[.1],[.1]),export_state_context(c))
    frequency_supported = PowerIO.from_powermodels(frequency_document(50.)).value.base_frequency==50.
    c50 = import_case(joinpath(@__DIR__,"..","data","case3.m")).case
    if frequency_supported
        # Construction preserves 50 Hz, but MATPOWER itself cannot encode it.
        @test !prepare_export(c50;format=:matpower,metadata=imported.metadata,
            options=ExportOptions(state_policy=:initial_guess)).accepted
    else
        @test_throws CaseIOError prepare_export(c50;format=:matpower,metadata=imported.metadata,
            options=ExportOptions(state_policy=:initial_guess))
    end

    # Programmatic case: sparse IDs, phase-shifting transformer, shunt and a
    # deliberately non-flat supplied state, independent of either reader.
    p = Case("export-fixture";base_power=200.,base_frequency=60.,
        network=ACNetwork([Bus(5;reference=true),Bus(10)],
            [Branch(7,5,10;resistance=.01,reactance=.12,
                tap_ratio=1.07,phase_shift=.08,thermal_limit=2.,kind=:transformer)];
            shunts=[FixedShunt(4,10;conductance=.001,susceptance=.02)]),
        generators=[Generator(42,5;p_min=0.,p_max=2.,q_min=-1.,q_max=1.,initial_p=.5,initial_q=.1)],
        loads=[Load(3,10;p=.5,q=.2)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    md = CaseIOMetadata()
    md.bus_base_kv[5]=230.; md.bus_base_kv[10]=115.
    state = ACState([1.03,.99],[0.,-.03],[.51],[.18])
    boundp = bind_export_state(state,export_state_context(p))
    original = DroopOPF._json_data(p)
    for format in (:matpower,:psse)
        plan = prepare_export(p;format,metadata=md,state=boundp)
        @test plan.accepted
        mktempdir() do dir
            path=joinpath(dir,format==:psse ? "result.raw" : "result.m")
            write_export(path,plan)
            for backend in (NativeBackend(),PowerIOBackend())
                if format==:psse && backend isa PowerIOBackend &&
                    !Base.get_extension(DroopOPF,:DroopOPFPowerIOExt)._raw_transformer_basis_qualified()
                    @test_throws CaseIOError import_case(path;backend,options=ImportOptions(base_frequency=60.))
                    continue
                end
                r=import_case(path;backend,options=ImportOptions(base_frequency=60.))
                @test r.initial_state.vm ≈ state.vm atol=1e-8
                @test r.initial_state.va ≈ state.va atol=1e-8
                @test r.initial_state.pg ≈ state.pg atol=1e-8
                @test r.initial_state.qg ≈ state.qg atol=1e-8
                @test r.case.network.branches[1].kind == :transformer
                @test r.case.network.branches[1].thermal_limit ≈ 2.
                @test DroopOPF._admittance_matrix(r.case.network) ≈ DroopOPF._admittance_matrix(p.network) atol=1e-8
                @test branch_flows(r.case.network,r.initial_state).from ≈ branch_flows(p.network,state).from atol=1e-7
            end
        end
    end
    @test DroopOPF._json_data(p)==original
    droop = VoltVarDroop(VoltageSchedule(1.0),.05,0.,
        ReactiveCapability(p_min=0.,p_max=2.,q_min=-1.,q_max=1.))
    controlled = attach_controls(p,[droop],[GeneratorControlAttachment(42,1,RegulatedLocation(:bus,5))])
    @test_throws CaseIOError prepare_export(controlled;format=:matpower,metadata=md,
        options=ExportOptions(state_policy=:initial_guess))
    snapshot = prepare_export(controlled;format=:matpower,metadata=md,
        options=ExportOptions(state_policy=:initial_guess,control_policy=:snapshot))
    @test snapshot.accepted
    @test any(d->d.code==:controls_projected_to_snapshot,snapshot.diagnostics)
    out_of_limits = ACState(state.vm,state.va,[2.5],[1.5])
    unbounded = prepare_export(p;format=:matpower,metadata=md,
        state=bind_export_state(out_of_limits,export_state_context(p)))
    @test unbounded.accepted
    @test any(d->d.code==:export_state_outside_limits,unbounded.diagnostics)
    mktempdir() do dir
        path=joinpath(dir,"dispatch.m");write_export(path,unbounded)
        readback=import_case(path)
        @test readback.initial_state.pg == [2.5]
        @test readback.initial_state.qg == [1.5]
    end
    # PSS/E cannot preserve symmetric charging on this transformer: the writer
    # projects it to one magnetizing branch. The loss must block installation.
    charged = Case("charged";base_power=p.base_power,base_frequency=p.base_frequency,
        network=ACNetwork(p.network.buses,
            [Branch(7,5,10;resistance=.01,reactance=.12,charging=.02,
                tap_ratio=1.07,phase_shift=.08,thermal_limit=2.,kind=:transformer)];shunts=p.network.shunts),
        loads=p.loads,generators=p.generators,controls=p.controls,attachments=p.attachments)
    rejected = prepare_export(charged;format=:psse,metadata=md,
        options=ExportOptions(state_policy=:initial_guess))
    @test !rejected.accepted
    @test any(d->d.code==:powerio_writer_notice && d.severity==:warning,rejected.diagnostics)
    mktempdir() do dir
        path=joinpath(dir,"existing.raw"); write(path,"keep")
        @test_throws CaseIOError write_export(path,rejected;overwrite=true)
        @test read(path,String)=="keep"
    end
    # Current case wins over retained input bytes; prior states become stale.
    plan = prepare_export(c;format=:matpower,context=imported,state=bound)
    previous = copy(plan.bytes)
    l = c.loads[1]
    c.loads[1] = Load(l.id,l.bus_id;p=l.p+.1,q=l.q)
    @test plan.bytes==previous
    @test_throws CaseIOError prepare_export(c;format=:matpower,context=imported,state=bound)
    changed = prepare_export(c;format=:matpower,context=imported,
        options=ExportOptions(state_policy=:initial_guess))
    @test changed.bytes != previous
    mktempdir() do dir
        path = joinpath(dir,"changed.m"); write_export(path,changed)
        @test load_case(path).loads[1].p ≈ l.p+.1
    end
    # Unknown source ratings remain a distinct export choice.
    md.branch_rating_mva[7] = nothing
    @test_throws CaseIOError prepare_export(p;format=:matpower,metadata=md,state=boundp)
    @test prepare_export(p;format=:matpower,metadata=md,state=boundp,
        options=ExportOptions(rating_policy=:source)).accepted
    @test prepare_export(p;format=:matpower,metadata=md,state=boundp,
        options=ExportOptions(rating_policy=:effective)).accepted
end
