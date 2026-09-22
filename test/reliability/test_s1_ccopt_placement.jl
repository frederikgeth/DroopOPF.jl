@testset "S1 CCOpt placement candidates" begin
    include(joinpath(@__DIR__,"..","..","examples","s1_ccopt_placement.jl"))
    source=joinpath(@__DIR__,"..","data","pglib","v23.07","pglib_opf_case118_ieee.m")
    original=load_matpower_case(source;base_frequency=60.)
    anchor=optimize_joint_design(original;initial_state=s1_flat(original))
    case,policies,_=s1_public_overlay(original,anchor,source;bank_count=12)
    candidates=s1_ccopt_placement_candidates(case,policies)
    @test candidates.tap_terminal.id != candidates.tap_remote.id
    @test candidates.bank_colocated.id != candidates.bank_remote.id
    @test !isempty(candidates.terminal_droop_controls)
    @test candidates.bank_colocated.bus_id in Set(a.location.bus_id for a in case.attachments)
    @test !(candidates.bank_remote.bus_id in Set(a.location.bus_id for a in case.attachments))
end
