using DroopOPF, JSON
import CCOpt
include("s1_ccopt_pilot.jl")

const S1_CCOPT_FAMILIES = (
    :fixed, :droop, :tap, :shunt, :tap_shunt, :tap_droop, :shunt_droop, :joint,
)

"""Select the same declared control family without changing case physics or bounds."""
function s1_ccopt_family(policies, family::Symbol; count::Int=1)
    family in S1_CCOPT_FAMILIES || error("unknown CCOpt family: $family")
    take(xs) = xs[1:min(count, length(xs))]
    use_tap = family in (:tap, :tap_shunt, :tap_droop, :joint)
    use_shunt = family in (:shunt, :tap_shunt, :shunt_droop, :joint)
    use_droop = family in (:droop, :tap_droop, :shunt_droop, :joint)
    (
        tap_controls=use_tap ? take(policies.tap_controls) : TapControl[],
        shunt_controls=use_shunt ? take(policies.shunt_controls) : ShuntControl[],
        droop_controls=use_droop ? take(policies.droop_controls) : DroopControl[],
    )
end

function s1_ccopt_profile(name::Symbol)
    name == :standard && return Dict{String,Any}()
    name == :tight && return Dict{String,Any}(
        "relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),
        "tol"=>1e-11, "acceptable_tol"=>1e-11,
    )
    error("unknown CCOpt accuracy profile: $name")
end
