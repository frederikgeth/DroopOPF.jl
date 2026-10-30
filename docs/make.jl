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
        "Index" => "index.md",
        "Getting Started" => "getting_started.md",
        "Data Model" => "data_model.md",
        "Case import and export" => "case_io.md",
        "PSS/E" => "psse.md",
        "Solvers" => "solvers.md",
        "Validation" => "validation.md",
        "Validation evidence" => [
            "Milestone index" => "milestones.md",
            "Reports" => "validation_reports.md",
            "Tables" => "validation_tables.md",
            "Figures" => "validation_figures.md",
            "Provenance and sharing" => "validation_evidence.md",
        ],
        "SCOPF" => "scopf.md",
        "Droop Optimization" => "droop_optimization.md",
        "Droop Security" => "droop_security.md",
        "Multi Period" => "multi_period.md",
        "Mixed AVR / droop" => "mixed_avr_droop.md",
        "Equipment Optimization" => "equipment_optimization.md",
        "Feasibility Gate" => "feasibility_gate.md",
        "Global Feasibility" => "global_feasibility.md",
        "Robustness" => "robustness.md",
        "API" => "api.md",
        "Development" => "development.md",
        "Release scope" => "release_scope.md",
        "Research evidence" => "research.md",
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
