using Documenter
using DroopOPF

DocMeta.setdocmeta!(DroopOPF, :DocTestSetup, :(using DroopOPF); recursive = true)

makedocs(
    sitename = "DroopOPF.jl",
    authors = "DroopOPF contributors",
    modules = [DroopOPF],
    repo = "https://github.com/frederikgeth/DroopOPF.jl/blob/{commit}{path}#L{line}",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://frederikgeth.github.io/DroopOPF.jl",
        repolink = "https://github.com/frederikgeth/DroopOPF.jl",
        edit_link = "main",
    ),
    pages = [
        "Home" => "index.md",
        "Getting started" => "getting_started.md",
        "Data model" => "data_model.md",
        "Solver formulations" => "solvers.md",
        "Validation" => "validation.md",
        "Security-constrained OPF" => "scopf.md",
        "M3 droop optimization" => "droop_optimization.md",
        "M4 robustness" => "robustness.md",
        "M4 scale-up decision" => "scale_up_decision.md",
        "M7 equipment optimization" => "equipment_optimization.md",
        "Milestones and S1 status" => "milestones.md",
        "S1 joint formulation" => "joint_formulation.md",
        "S1 convergence evidence" => "s1_evidence.md",
        "S1 extended studies" => "s1_extension.md",
        "S1 scaling and failure locations" => "s1_scaling.md",
        "S1 primal/dual restarts" => "s1_warmstarts.md",
        "S1 bounded restart policy" => "s1_restart_policy.md",
        "S1 controller normalization" => "s1_normalization.md",
        "S1 staged initialization" => "s1_staged.md",
        "S1 stationarity and active bounds" => "s1_kkt.md",
        "S1 implied droop Q bounds" => "s1_implied_q.md",
        "S1 reduced droop Q formulation" => "s1_reduced_q.md",
        "S1 CCOpt pilot and frozen lane" => "s1_ccopt.md",
        "S1 feasibility audit" => "s1_feasibility.md",
        "Examples" => "examples.md",
        "API reference" => "api.md",
        "Development" => "development.md",
    ],
    checkdocs = :exports,
)

if get(ENV, "DOCUMENTER_DEPLOY", "false") == "true"
    deploydocs(
        repo = "github.com/frederikgeth/DroopOPF.jl.git",
        devbranch = "main",
        push_preview = true,
    )
end
