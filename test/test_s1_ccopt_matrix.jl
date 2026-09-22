@testset "S1 CCOpt matched matrix helpers" begin
    include(joinpath(@__DIR__,"..","examples","s1_ccopt_matrix.jl"))
    case=m72_case()
    p=(tap_controls=[TapControl(11;lower=.95,upper=1.05)],
        shunt_controls=[ShuntControl(201)],
        droop_controls=[DroopControl(2;slope_bounds=(.04,.1))])
    expected=Dict(
        :fixed=>(0,0,0), :droop=>(0,0,1), :tap=>(1,0,0), :shunt=>(0,1,0),
        :tap_shunt=>(1,1,0), :tap_droop=>(1,0,1), :shunt_droop=>(0,1,1), :joint=>(1,1,1),
    )
    for family in S1_CCOPT_FAMILIES
        selected=s1_ccopt_family(p,family)
        @test (length(selected.tap_controls),length(selected.shunt_controls),length(selected.droop_controls)) == expected[family]
    end
    @test isempty(s1_ccopt_profile(:standard))
    @test s1_ccopt_profile(:tight)["tol"] == 1e-11
    @test_throws ErrorException s1_ccopt_family(p,:unknown)
end
