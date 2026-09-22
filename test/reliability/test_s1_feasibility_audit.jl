include(joinpath(@__DIR__,"..","..","examples","s1_feasibility_audit.jl"))

@testset "S1 public feasibility audit" begin
    source=joinpath(@__DIR__,"..","..","artifacts","s1_public_controls","summary.json")
    mktempdir() do out
        audit=s1_feasibility_audit(source,out)
        @test audit["all_groups_have_validated_witness"]
        @test length(audit["groups"])==6
        @test all(g["validated_witnesses"]>0 for g in values(audit["groups"]))
        @test audit["groups"]["public118_load1.05"]["attempts"]==6
        @test audit["groups"]["public300_load1.05"]["attempts"]==6
    end
end
