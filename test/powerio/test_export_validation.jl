@testset "Export constructor integrity and scale" begin
    fixture = joinpath(@__DIR__,"..","data","case3.m")
    c = load_case(fixture;options=ImportOptions(base_frequency=60.))
    expected = PowerIO.to_powermodels(PowerIO.parse(fixture))
    ext = Base.get_extension(DroopOPF,:DroopOPFPowerIOExt)
    @test isnothing(ext._check_export_construction(PowerIO.from_powermodels(expected).value,expected,c))
    # Independent corruptions include state and limits that an admittance-only
    # check would never observe, and an outage that changes network semantics.
    for (table,row,field,change) in (("bus","1","vm",.02),
        ("gen","1","qmin",.1), ("gen","1","pg",.1),
        ("load","1","pd",.1), ("branch","1","rate_a",.1),
        ("branch","1","br_r",.01), ("branch","1","br_status",-1))
        changed = deepcopy(expected)
        changed[table][row][field] += change
        err = try
            ext._check_export_construction(PowerIO.from_powermodels(changed).value,expected,c)
        catch e
            e
        end
        @test err isa CaseIOError
        @test err.code == :export_construction_mismatch
    end
    # Exercise the public path on a network large enough to expose accidental
    # dense construction, with more than nine equipment indices (numeric order).
    n = 1024
    large = Case("linear-export";base_power=200.,base_frequency=60.,
        network=ACNetwork([Bus(i;reference=i==1) for i in 1:n],
            [Branch(i,i,i+1;resistance=.01,reactance=.1,thermal_limit=2.) for i in 1:n-1]),
        generators=[Generator(77,1;p_min=0.,p_max=2.,q_min=-1.,q_max=1.,initial_p=.2,initial_q=.1)],
        loads=[Load(15,n;p=.2,q=.1)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    md = CaseIOMetadata()
    merge!(md.bus_base_kv, Dict(i=>220. for i in 1:n))
    plan = prepare_export(large;format=:matpower,metadata=md,options=ExportOptions(state_policy=:initial_guess))
    @test plan.accepted
    reparsed = PowerIO.parse(PowerIO.PioModule{PowerIO.BalancedNetwork},plan.bytes;format="matpower")
    @test length(reparsed.value.buses) == n
    @test length(reparsed.value.branches) == n-1
    @test reparsed.value.generators[1].bus_id == 1
    @test reparsed.value.loads[1].bus_id == n
end
