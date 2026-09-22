module DroopOPF

include("curves.jl")
include("controls.jl")
include("network.jl")
include("domain.jl")
include("contingencies.jl")
include("physics.jl")
include("matpower.jl")
include("jump.jl")
include("complementarity.jl")
include("scopf.jl")
include("validation.jl")
include("scopf_validation.jl")
include("multistart.jl")
include("diagnostics.jl")
include("scopf_io.jl")
include("benchmarking.jl")
include("plotting.jl")
include("scopf_plotting.jl")
include("droop_sweep.jl")
include("droop_optimization.jl")
include("droop_design_multistart.jl")
include("droop_design_plotting.jl")
include("tap_optimization.jl")
include("shunt_optimization.jl")
include("joint_design.jl")
export DroopControl, JointDesignResult, optimize_joint_design, with_joint_settings
export validate_joint_design, exact_droop_audit, joint_design_metrics, write_joint_design, read_joint_design
export ShuntControl, ShuntOPFResult, optimize_shunts, with_shunt_settings
export validate_shunt_design, shunt_design_metrics, write_shunt_design, read_shunt_design
export TapControl, TapOPFResult, optimize_taps, with_tap_settings, validate_tap_design
export write_tap_design, read_tap_design, tap_design_metrics

export write_study, read_study, write_scopf_result, read_scopf_result, write_scopf_report
export write_scopf_multistart, write_scopf_diagnostics
export Contingency, Study, scenario_case, SCOPFResult, solve_scopf
export evaluate_contingencies, solve_scopf_continuation, SCOPFReport
export SCOPFMultiStartRun, SCOPFMultiStartResult, solve_scopf_multistart
export DroopBreakpointDiagnostic, SCOPFFinding, SCOPFDiagnostics, scopf_diagnostics
export SCOPFBenchmarkSample, SCOPFBenchmarkReport, benchmark_scopf, write_scopf_benchmark
export PiecewiseLinearCurve, evaluate, slope_at
export RegulatedLocation, VoltageSchedule, ReactiveCapability, VoltVarDroop
export droop_response, droop_curve
export Generator, GeneratorControlAttachment, Case, validate_case
export load_matpower_case, attach_controls
export Bus, Branch, Load, FixedShunt, ShuntBank, ACNetwork, ACState, shunt_powers
export with_bank_state, bank_admittance, bank_powers
export power_balance, branch_flows, operating_margins
export droop_residual, equilibrium_residual
export ACOPFResult, ACOPFContinuationResult, solve, solve_opf, solve_opf_continuation
export reactive_smoothing_epsilon
export ComplementarityOPFResult, solve_opf_complementarity
export ccopt_diagnostics, ccopt_encoding_audit
export EquilibriumValidationReport, EquilibriumReport, validate_equilibrium
export equilibrium_report, markdown_report
export DroopOperatingPoint, droop_regime, droop_operating_point, droop_operating_points
export solver_operating_points, write_droop_plot, write_solver_comparison_plot
export scopf_operating_points, write_scopf_droop_plot, write_scopf_voltage_plot
export write_scopf_branch_loading_plot, write_scopf_dispatch_plot
export write_scopf_residual_plot, write_scopf_validation_plots
export DroopSlopeSweepPoint, DroopSlopeSweep, sweep_droop_slope, best_droop_slope
export write_droop_slope_sweep, read_droop_slope_sweep, write_droop_slope_sweep_plot
export DroopSettings, DroopDesignResult, with_droop_settings
export optimize_droop_parameters, validate_droop_design, evaluate_held_out_contingencies
export write_droop_design, read_droop_design
export DroopDesignMultiStartRun, DroopParameterSpread, DroopDesignMultiStartResult
export optimize_droop_multistart, write_droop_design_multistart
export write_droop_design_comparison_plot

end
