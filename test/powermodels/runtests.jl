using Test, DroopOPF, PowerModels

@testset "Prepared network staged design and persistence" begin
    data = PowerModels.parse_file(joinpath(@__DIR__, "../data/case3.m"))
    ids = sort!(collect(keys(data["gen"])))
    regulation = Dict("free_dispatch"=>ids, "shared_droop_groups"=>Dict(),
        "avr_targets"=>Dict(), "avr_plants"=>Dict(), "fixed_q"=>String[],
        "reserve_participants"=>ids)
    equipment = Dict("selected"=>Dict(), "policy"=>"fixed")
    contract = NetworkDesignContract(data, Dict(), regulation, equipment)
    digest = network_contract_digest(contract)
    @test Base.get_extension(DroopOPF, :DroopOPFPowerModelsExt) !== nothing
    @test_throws ArgumentError NetworkDesignContract(merge(data, Dict("per_unit"=>false)), Dict(), regulation, equipment)
    @test_throws ErrorException solve_network_design(contract; max_iterations=0)
    result = solve_network_design(contract; hessian="exact")
    @test result["accepted"]
    @test replay_network_design(contract, result)
    @test network_contract_digest(contract) == digest
    @test result["stage_order"] == ["feasibility", "initialization", "design-feasibility", "design"]
    @test result["reserve_floor"] > 0
    @test result["stages"]["design"]["replay"]["reserve"] >= result["reserve_floor"] - 1e-8
    mktempdir() do directory
        cp = joinpath(directory, "contract.json")
        rp = joinpath(directory, "result.json")
        write_network_contract(cp, contract)
        @test network_contract_digest(read_network_contract(cp)) == digest
        write_network_design(rp, result)
        @test read_network_design(rp, contract)["accepted"]
        @test_throws ArgumentError write_network_design(rp, result)
    end
    corrupted = deepcopy(result)
    corrupted["stages"]["design"]["data"]["gen"][first(ids)]["pg"] += .1
    @test_throws ErrorException replay_network_design(contract, corrupted)
    corrupted = deepcopy(result)
    corrupted["reserve_floor"] += .01
    @test_throws ErrorException replay_network_design(contract, corrupted)
end
