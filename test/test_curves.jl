@testset "piecewise-linear curves" begin
    curve = PiecewiseLinearCurve([0.0, 1.0, 2.0], [2.0, 0.0, -2.0])

    @test evaluate(curve, 0.0) == 2.0
    @test evaluate(curve, 0.5) == 1.0
    @test evaluate(curve, 1.5) == -1.0
    @test evaluate(curve, -1.0) == 2.0
    @test evaluate(curve, 3.0) == -2.0
    @test slope_at(curve, 0.5) == -2.0
    @test slope_at(curve, -1.0) == 0.0

    linear = PiecewiseLinearCurve([0.0, 1.0], [0.0, 2.0]; extrapolation = :linear)
    @test evaluate(linear, -1.0) == -2.0
    @test evaluate(linear, 2.0) == 4.0

    strict = PiecewiseLinearCurve([0.0, 1.0], [0.0, 1.0]; extrapolation = :error)
    @test_throws DomainError evaluate(strict, -1.0)
    @test_throws ArgumentError PiecewiseLinearCurve([0.0, 0.0], [0.0, 1.0])
    @test_throws ArgumentError PiecewiseLinearCurve([0.0], [0.0])
end
