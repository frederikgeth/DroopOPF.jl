"""A strictly increasing, piecewise-linear scalar curve."""
struct PiecewiseLinearCurve{T<:Real}
    breakpoints::Vector{T}
    values::Vector{T}
    extrapolation::Symbol

    function PiecewiseLinearCurve{T}(
        breakpoints::Vector{T},
        values::Vector{T},
        extrapolation::Symbol,
    ) where {T<:Real}
        length(breakpoints) == length(values) ||
            throw(ArgumentError("breakpoints and values must have the same length"))
        length(breakpoints) >= 2 ||
            throw(ArgumentError("a piecewise-linear curve needs at least two points"))
        all(isfinite, breakpoints) ||
            throw(ArgumentError("curve breakpoints must be finite"))
        all(isfinite, values) ||
            throw(ArgumentError("curve values must be finite"))
        all(diff(breakpoints) .> zero(T)) ||
            throw(ArgumentError("curve breakpoints must be strictly increasing"))
        extrapolation in (:clamp, :linear, :error) ||
            throw(ArgumentError("extrapolation must be :clamp, :linear, or :error"))
        new{T}(copy(breakpoints), copy(values), extrapolation)
    end
end

function PiecewiseLinearCurve(
    breakpoints::AbstractVector{T},
    values::AbstractVector{T};
    extrapolation::Symbol = :clamp,
) where {T<:Real}
    return PiecewiseLinearCurve{T}(collect(breakpoints), collect(values), extrapolation)
end

function _segment(curve::PiecewiseLinearCurve, x::Real)
    xs = curve.breakpoints
    n = length(xs)

    if x < xs[1]
        curve.extrapolation == :error && throw(DomainError(x, "below curve domain"))
        return 1
    elseif x > xs[end]
        curve.extrapolation == :error && throw(DomainError(x, "above curve domain"))
        return n - 1
    end

    i = searchsortedlast(xs, x)
    return min(max(i, 1), n - 1)
end

function evaluate(curve::PiecewiseLinearCurve, x::Real)
    isfinite(x) || throw(DomainError(x, "curve input must be finite"))
    xs = curve.breakpoints
    ys = curve.values

    if curve.extrapolation == :clamp && x <= xs[1]
        return ys[1]
    elseif curve.extrapolation == :clamp && x >= xs[end]
        return ys[end]
    end

    i = _segment(curve, x)
    α = (x - xs[i]) / (xs[i + 1] - xs[i])
    return (one(α) - α) * ys[i] + α * ys[i + 1]
end

function slope_at(curve::PiecewiseLinearCurve, x::Real)
    isfinite(x) || throw(DomainError(x, "curve input must be finite"))
    if curve.extrapolation == :clamp &&
       (x <= first(curve.breakpoints) || x >= last(curve.breakpoints))
        return zero(eltype(curve.values))
    end
    i = _segment(curve, x)
    return (curve.values[i + 1] - curve.values[i]) /
           (curve.breakpoints[i + 1] - curve.breakpoints[i])
end
