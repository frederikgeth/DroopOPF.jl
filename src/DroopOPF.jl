module DroopOPF

include("curves.jl")
include("controls.jl")
include("network.jl")
include("domain.jl")
include("physics.jl")

export PiecewiseLinearCurve, evaluate, slope_at
export RegulatedLocation, VoltageSchedule, ReactiveCapability, VoltVarDroop
export droop_response, droop_curve
export Generator, GeneratorControlAttachment, Case, validate_case
export Bus, Branch, Load, ACNetwork, ACState
export power_balance, branch_flows, operating_margins
export droop_residual, equilibrium_residual

end
