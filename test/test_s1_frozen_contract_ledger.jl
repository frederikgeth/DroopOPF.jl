using JSON

include(joinpath(@__DIR__, "..", "examples", "s1_frozen_contract_ledger.jl"))

@testset "S1 frozen contract ledger" begin
    mktempdir() do tmp
        solver_dir = joinpath(tmp, "solver")
        mkpath(solver_dir)
        attempt_name = "synthetic5-load1.0-ipopt-anchor-attempt1"
        write(joinpath(solver_dir, attempt_name * "-design.json"), "{}\n")
        write(joinpath(solver_dir, attempt_name * "-diagnostics.json"), "{}\n")
        write(joinpath(solver_dir, attempt_name * "-start.json"), "{}\n")
        attempt = Dict(
            "name" => attempt_name,
            "status" => "ITERATION_LIMIT",
            "solver_valid" => false,
            "policy_valid" => false,
            "physical_valid" => false,
            "physical" => Dict(
                "power_balance_max" => 1e-3,
                "droop_residual_max" => 2e-3,
                "smooth_exact_droop_gap" => 1e-6,
                "violations" => ["power_balance", "droop"],
            ),
            "tags" => Dict(
                "context" => "context-hash",
                "dual_reset" => "none",
                "builder_start_overridden" => false,
            ),
        )
        row = Dict(
            "name" => "synthetic5-load1.0-ipopt-anchor",
            "buses" => 5,
            "solver" => "ipopt",
            "valid" => false,
            "tags" => Dict("load_factor" => 1.0, "start" => "anchor"),
            "events" => ["budget_exhausted"],
            "attempts" => [attempt],
        )
        summary = joinpath(solver_dir, "summary.json")
        write(summary, JSON.json([row]))
        feasibility = joinpath(tmp, "feasibility.json")
        write(feasibility, JSON.json(Dict("groups" => Dict(
            "public5_load1.0" => Dict("witnesses" => ["known-valid-cell"]),
        ))))

        out = joinpath(tmp, "out")
        ledger = s1_frozen_contract_ledger(summary, summary, feasibility, out;
            enforce_contract=false)
        @test ledger["cell_count"] == 2
        @test ledger["classifications"] == Dict("solver_path_failure_with_witness" => 2)
        cell = only(filter(c -> c["solver"] == "ipopt", ledger["cells"])[1:1])
        @test cell["known_witnesses"] == ["known-valid-cell"]
        @test cell["strict_residuals"]["power_balance_max"] == 1e-3
        @test cell["last_retained_iterate"] ==
            relpath(joinpath(solver_dir, attempt_name * "-design.json"), pwd())
        @test cell["seed_lineage"][1]["context"] == "context-hash"
        @test isfile(joinpath(out, "contract-ledger.json"))
    end
end
