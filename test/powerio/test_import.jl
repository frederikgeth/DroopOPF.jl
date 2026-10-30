@testset "PowerIO parallel imports and electrical equivalence" begin
    data = joinpath(@__DIR__, "..", "data")
    transformer_record = "1,2,0,'T1',1,1,1,0,0,2,'T / A',1,1,1\n.01,.2,50\n1.05,220,5,100,110,120,0,0,1.1,.9,1.1,.9,33,0,0,0,0\n.98,110\n"
    raw_source = read(joinpath(data,"psse","synthetic_v33.raw"),String)
    @test occursin(transformer_record,raw_source)
    raw_profile = replace(raw_source,transformer_record=>"")
    qualified = Base.get_extension(DroopOPF,:DroopOPFPowerIOExt)._raw_transformer_basis_qualified()
    @info "Loaded RAW transformer basis qualification" qualified
    mktempdir() do paritydir
    v33 = joinpath(paritydir,"qualified_v33.raw"); write(v33,qualified ? raw_source : raw_profile)
    # The original v34 fixture deliberately carries a dangling regulation node.
    # Qualify its static network with that unsupported reference removed.
    v34 = joinpath(paritydir,"qualified_v34.raw")
    text34 = read(joinpath(data,"psse","synthetic_v34.raw"),String)
    if !qualified
        firstline = findfirst("1,2,0,'T1'",text34).start
        lastline = findnext("0 / END OF TRANSFORMER",text34,firstline).start
        text34 = text34[1:prevind(text34,firstline)] * text34[lastline:end]
    end
    write(v34, replace(text34,",0,1,7\n" => ",0,1,0\n"))
    for path in (joinpath(data,"case3.m"), v33, v34)
        native = import_case(path)
        external = import_case(path; backend=PowerIOBackend())
        c, x = native.case, external.case
        @test external.source.backend == :powerio
        @test external.source.parser_version == string(pkgversion(PowerIO))
        @test external.source.sha256 == native.source.sha256
        @test x.base_power == c.base_power
        @test x.base_frequency == c.base_frequency
        @test [b.kind for b in x.network.branches] == [b.kind for b in c.network.branches]
        @test external.metadata.branch_rating_mva == native.metadata.branch_rating_mva
        @test external.metadata.bus_base_kv == native.metadata.bus_base_kv
        @test all(==(:unknown), external.metadata.saved_field_presence[:PG])
        @test any(d -> d.code==:saved_field_presence_unknown, external.diagnostics)
        @test external.initial_state.pg ≈ native.initial_state.pg
        @test external.initial_state.qg ≈ native.initial_state.qg
        @test external.initial_state.vm ≈ native.initial_state.vm
        @test external.initial_state.va ≈ native.initial_state.va
        @test DroopOPF._admittance_matrix(x.network) ≈ DroopOPF._admittance_matrix(c.network) atol=1e-12
        for (a,b) in zip(x.network.branches,c.network.branches)
            @test collect(DroopOPF._branch_admittances(a)) ≈ collect(DroopOPF._branch_admittances(b)) atol=1e-12
        end
        # Check several off-nominal states; agreement at a flat voltage is weak.
        for delta in (0., .03, -.02)
            s = external.initial_state
            state = ACState(s.vm .+ delta, s.va .+ delta, s.pg, s.qg)
            @test power_balance(x,state).vector ≈ power_balance(c,state).vector atol=1e-12
            @test branch_flows(x.network,state).from ≈ branch_flows(c.network,state).from atol=1e-12
        end
        # Cross-check against PowerIO's independently assembled bus-mapped Ybus.
        n = PowerIO.parse(path).value
        mapped = PowerIO.calc_admittance_matrix(n)
        order = [mapped.bus_to_idx[b.id] for b in x.network.buses]
        @test DroopOPF._admittance_matrix(x.network) ≈ Matrix(mapped.matrix)[order,order] atol=1e-12
    end
    end
    @test_throws CaseIOError import_case(joinpath(data,"psse","synthetic_v34.raw"); backend=PowerIOBackend())
    if qualified
        original = import_case(joinpath(data,"psse","synthetic_v33.raw");backend=PowerIOBackend())
        @test original.case.network.branches[2].kind==:transformer
        @test any(d->d.code==:raw_transformer_basis_qualified,original.diagnostics)
    else
        original_error = try import_case(joinpath(data,"psse","synthetic_v33.raw");backend=PowerIOBackend()); catch e; e; end
        @test original_error isa CaseIOError
        @test original_error.code == :unqualified_raw_transformer
    end
    @test_throws CaseIOError import_case(joinpath(data,"psse","synthetic_v36.raw"); backend=PowerIOBackend())
    mktempdir() do dir
        raw = raw_profile
        path = joinpath(dir,"case.raw")
        # Constant-current load terms must not disappear after successful parse.
        write(path, replace(raw,"60,20,0,0,0,0"=>"60,20,2,0,0,0"))
        err = try import_case(path; backend=PowerIOBackend()); catch e; e; end
        @test err isa CaseIOError
        @test err.code == :unsupported_load_model
        # Preserve transformer outage association by rejecting extra end shunts.
        write(path, replace(raw,"100,110,120,0,0,0,0,1"=>"100,110,120,.01,0,0,0,1"))
        err = try import_case(path; backend=PowerIOBackend()); catch e; e; end
        @test err isa CaseIOError
        @test err.code == :unsupported_terminal_admittance
        # Power conversion must not assume a 100 MVA system base.
        write(path, replace(raw,"0,100,33"=>"0,200,33"))
        x = import_case(path; backend=PowerIOBackend()).case
        @test x.loads[1].p == .3
        # Independently check the original two-ideal-winding circuit. Stock
        # libraries must reject these cases; corrected builds must import them.
        for base in (100.,200.), nominal in (false,true), cw in 1:3, cz in 1:3
            wind1 = cw==2 ? 231. : 1.05
            wind2 = cw==2 ? 107.8 : .98
            nom1, nom2 = nominal ? (230.,115.) : (0.,0.)
            resistance = cz==3 ? 50000. : .01
            text = replace(raw_source,
                "0,100,33"=>"0,$base,33",
                "'T1',1,1,1"=>"'T1',$cw,$cz,1",
                ".01,.2,50\n"=>"$resistance,.2,50\n",
                "1.05,220,5"=>"$wind1,$nom1,5",
                ".98,110\n"=>"$wind2,$nom2\n")
            write(path,text)
            if !qualified
                err = try import_case(path;backend=PowerIOBackend()); catch e; e; end
                @test err isa CaseIOError
                @test err.code == :unqualified_raw_transformer
                continue
            end
            imported=import_case(path;backend=PowerIOBackend())
            b=only(filter(b->b.kind==:transformer,imported.case.network.branches))
            r=cz==3 ? .001 : .01
            x=cz==3 ? sqrt(.2^2-r^2) : .2
            scale=cz==1 ? 1. : base/50*(nominal ? (230/220)^2 : 1.)
            z=complex(r,x)*scale
            a=cw==2 ? 231/220 : cw==3 && nominal ? 1.05*230/220 : 1.05
            d=cw==2 ? 107.8/110 : cw==3 && nominal ? .98*115/110 : .98
            t=a*cis(deg2rad(5.))
            expected=[1/(z*abs2(t)) -1/(z*conj(t)*d); -1/(z*t*d) 1/(z*d^2)]
            actual=transpose(reshape(collect(DroopOPF._branch_admittances(b)),2,2))
            @test actual ≈ expected atol=1e-12
            native=import_case(path)
            @test DroopOPF._admittance_matrix(imported.case.network) ≈ DroopOPF._admittance_matrix(native.case.network) atol=1e-12
            # Check a non-flat state and transformer outage association, too.
            s=imported.initial_state
            @test branch_flows(imported.case.network,s).from ≈ branch_flows(native.case.network,s).from atol=1e-12
        end
    end
end
