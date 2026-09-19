using JSON

@testset "M5.1 transformer data contract" begin
    fixture = joinpath(@__DIR__, "data", "transformer3.m")
    c = load_matpower_case(fixture)
    b = c.network.branches[1]
    @test b.tap_ratio == 1.05
    @test b.phase_shift ≈ pi / 18
    @test c.network.branches[2].tap_ratio == 1
    @test c.network.branches[2].phase_shift == 0
    old = Branch{Float64}(9, 1, 2, .01, .1, 0., 2., true)
    @test (old.tap_ratio, old.phase_shift) == (1., 0.)
    @test Branch(9, 1, 2; resistance=.01, reactance=.1, thermal_limit=2.).tap_ratio == 1
    for value in (0., -1., Inf, NaN)
        @test_throws ArgumentError Branch(1,1,2; resistance=.01, reactance=.1,
            thermal_limit=2., tap_ratio=value)
    end
    for value in (Inf, -Inf, NaN)
        @test_throws ArgumentError Branch(1,1,2; resistance=.01, reactance=.1,
            thermal_limit=2., phase_shift=value)
    end
    promoted = ACNetwork([Bus(1; v_min=big"0.9"), Bus(2)], [b])
    @test promoted.branches[1].tap_ratio == BigFloat(b.tap_ratio)
    @test promoted.branches[1].phase_shift == BigFloat(b.phase_shift)
    copied = Case("promoted"; base_power=big"100", base_frequency=50,
        network=c.network, generators=c.generators, loads=c.loads,
        controls=c.controls, attachments=c.attachments)
    @test copied.network.branches[1].tap_ratio == BigFloat(b.tap_ratio)
    @test copied.network.branches[1].phase_shift == BigFloat(b.phase_shift)
    @test attach_controls(c, c.controls, c.attachments).network.branches[1] == b
    outage = Contingency(:line1; branch_ids=[1])
    overlay = scenario_case(c, outage)
    @test !overlay.network.branches[1].available
    @test overlay.network.branches[1].tap_ratio == b.tap_ratio
    @test overlay.network.branches[1].phase_shift == b.phase_shift
    @test c.network.branches[1].available
    other = scenario_case(c, Contingency(:line2; branch_ids=[2]))
    @test other.network.branches[1] == b
    state = ACState(ones(3), zeros(3), [1., .2], zeros(2))
    @test all(isfinite, power_balance(c,state).vector)
    @test all(isfinite, branch_flows(c.network,state).from)
    # An unavailable transformer injects no current, regardless of stored settings.
    @test branch_flows(overlay.network,state).from[1] == 0
    @test all(isfinite, power_balance(overlay,state).vector)
    for (tap, shift) in ((1.05, 0.), (1., .1))
        isolated = ACNetwork([Bus(1),Bus(2)], [Branch(1,1,2;
            resistance=.01, reactance=.1, thermal_limit=2., tap_ratio=tap, phase_shift=shift)])
        @test all(isfinite, branch_flows(isolated, ACState(ones(2),zeros(2),Float64[],Float64[])).from)
    end
    mktempdir() do dir
        path = joinpath(dir,"study.json")
        study = Study(c; contingencies=[outage], participation=Dict(1=>1.))
        write_study(path,study)
        doc = JSON.parsefile(path)
        @test doc["schema_version"] == 4
        restored = read_study(path)
        @test restored.case.network.branches == c.network.branches
        @test scenario_case(restored.case,restored.contingencies[1]).network.branches == overlay.network.branches
        delete!(doc["data"]["case"]["network"]["branches"][1], "tap_ratio")
        write(path, JSON.json(doc))
        @test_throws ArgumentError read_study(path)
        doc["schema_version"] = 1
        write(path,JSON.json(doc))
        @test_throws ArgumentError read_study(path) # phase metadata must not disappear
        for branch in doc["data"]["case"]["network"]["branches"]
            delete!(branch,"tap_ratio"); delete!(branch,"phase_shift")
        end
        write(path,JSON.json(doc))
        legacy = read_study(path)
        @test all(x.tap_ratio == 1 && x.phase_shift == 0 for x in legacy.case.network.branches)
        doc["schema_version"] = 99
        write(path,JSON.json(doc))
        @test_throws ArgumentError read_study(path)
        # Transformer metadata does not change unrelated result/report schema versions.
        DroopOPF._write_scopf_json(path,"DroopOPF.SCOPFReport",Dict("valid"=>false))
        @test JSON.parsefile(path)["schema_version"] == 1
        source = read(fixture,String)
        for replacement in ("0.0 0.0 1 0 1", "0.0 0.0 0 1 1")
            path = joinpath(dir,"shunt.m")
            write(path,replace(source,"0.0 0.0 0 0 1"=>replacement))
            @test length(load_matpower_case(path).network.shunts) == 1
        end
    end
end

include(joinpath(@__DIR__, "..", "examples", "m5_1_transformer_data.jl"))
@testset "M5.1 reproducible evidence" begin
    mktempdir() do dir
        @test transformer_data_evidence(dir)["pass"]
        @test JSON.parsefile(joinpath(dir,"evidence.json"))["physical_validity"] == "not evaluated"
        @test occursin("JSON round trip",read(joinpath(dir,"report.md"),String))
        @test occursin("From-side complex tap",read(joinpath(dir,"transformer_orientation.svg"),String))
    end
end
