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
