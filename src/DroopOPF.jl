module DroopOPF

include("curves.jl")
include("controls.jl")
include("network.jl")
include("domain.jl")
include("physics.jl")
include("matpower.jl")
include("jump.jl")
include("validation.jl")

export PiecewiseLinearCurve, evaluate, slope_at
export RegulatedLocation, VoltageSchedule, ReactiveCapability, VoltVarDroop
export droop_response, droop_curve
export Generator, GeneratorControlAttachment, Case, validate_case
export load_matpower_case, attach_controls
export Bus, Branch, Load, ACNetwork, ACState
export power_balance, branch_flows, operating_margins
export droop_residual, equilibrium_residual
export ACOPFResult, solve, solve_opf
export EquilibriumValidationReport, validate_equilibrium

end
