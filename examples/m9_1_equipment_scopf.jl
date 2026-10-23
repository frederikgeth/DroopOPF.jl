using DroopOPF

include(joinpath(@__DIR__, "m2_case.jl"))

output_directory = isempty(ARGS) ? joinpath(pwd(), "m9_1_equipment_scopf") : ARGS[1]
mkpath(output_directory)

source = m2_case()
bank = ShuntBank(201, 30;
    step_susceptances=(0.02,),
    step_conductances=(0.0,),
    legal_states=((0,), (1,), (2,), (3,)),
    state=(1,),
    nominal_state=(1,),
)
case = Case("m9.1-equipment-scopf";
    base_power=source.base_power,
    base_frequency=source.base_frequency,
    network=ACNetwork(source.network.buses, source.network.branches;
        shunts=source.network.shunts, banks=[bank]),
    loads=source.loads,
    generators=source.generators,
    controls=source.controls,
    attachments=source.attachments,
)

contingencies = [
    Contingency(:line_22; branch_ids=[22]),
    Contingency(:generator_9; generator_ids=[9]),
]
participation = Dict(7 => 2.0, 9 => 1.0)

# Stage the enlarged equipment model from a validated fixed-equipment SCOPF.
seed_study = Study(source;
    contingencies,
    participation,
    reactive_assignments=reactive_control_assignments(source),
)
seed = solve_scopf(seed_study; smooth_epsilon=1e-5)
equilibrium_report(seed_study, seed).valid || error("fixed-equipment seed is invalid")

tap_controls = [
    TapControl(11; lower=0.95, upper=1.05, initial=1.0, nominal=1.0),
]
shunt_controls = [
    ShuntControl(201; lower=0.0, upper=0.06, initial=0.02, nominal=0.02),
]
preventive_study = Study(case;
    contingencies,
    participation,
    reactive_assignments=reactive_control_assignments(case),
    tap_controls,
    shunt_controls,
    control_policy=SCOPFControlPolicy(taps=:preventive, shunts=:preventive),
)
preventive = solve_scopf(preventive_study;
    smooth_epsilon=1e-5, initial_states=seed.states)
preventive_report = equilibrium_report(preventive_study, preventive)
preventive_report.valid || error("preventive equipment SCOPF is invalid")

# Corrective timing permits a bounded setting per scenario. Start from the
# validated preventive design; no movement-speed or discrete-action claim is made.
corrective_study = Study(case;
    contingencies,
    mode=:corrective,
    redispatch_limits=Dict(7 => 0.8, 9 => 0.8),
    reactive_assignments=reactive_control_assignments(case),
    tap_controls=[TapControl(11; lower=0.95, upper=1.05,
        initial=preventive.tap_settings[:base][11], nominal=1.0)],
    shunt_controls=[ShuntControl(201; lower=0.0, upper=0.06,
        initial=preventive.shunt_settings[:base][201], nominal=0.02)],
    control_policy=SCOPFControlPolicy(taps=:corrective, shunts=:corrective),
)
corrective = solve_scopf(corrective_study;
    smooth_epsilon=1e-5, initial_states=preventive.states)
corrective_report = equilibrium_report(corrective_study, corrective)
corrective_report.valid || error("corrective equipment SCOPF is invalid")

for (name, study, result, report) in (
    ("preventive", preventive_study, preventive, preventive_report),
    ("corrective", corrective_study, corrective, corrective_report),
)
    write_study(joinpath(output_directory, "$(name)-study.json"), study)
    write_scopf_result(joinpath(output_directory, "$(name)-result.json"), result)
    write_scopf_report(joinpath(output_directory, "$(name)-report.json"), report)
    write(joinpath(output_directory, "$(name)-report.md"), markdown_report(report) * "\n")
end

println("M9.1 preventive and corrective workflows validated in $(output_directory)")
