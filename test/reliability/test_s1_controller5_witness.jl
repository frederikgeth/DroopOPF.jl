include(joinpath(@__DIR__, "..", "..", "examples", "s1_controller5_witness_audit.jl"))

@testset "S1 controller-5 witness replay" begin
    mktempdir() do out
        audit = s1_controller5_witness_audit(out)
        @test length(audit["rows"]) == 2
        @test all(row["classification"] == "solver_path_failure_with_witness"
                  for row in audit["rows"])
        @test all(model["valid"] for row in audit["rows"]
                  for model in values(row["replayed_models"]))
        @test all(!path["strict_accepted"] for row in audit["rows"]
                  for path in row["failed_direct_paths"])
    end
end
