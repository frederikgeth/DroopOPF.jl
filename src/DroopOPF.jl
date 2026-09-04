module DroopOPF

include("curves.jl")
include("controls.jl")
include("domain.jl")

export PiecewiseLinearCurve, evaluate, slope_at
export RegulatedLocation, VoltageSchedule, ReactiveCapability, VoltVarDroop
export droop_response, droop_curve
export Generator, GeneratorControlAttachment, Case, validate_case

end
