using Documenter
using DroopOPF

DocMeta.setdocmeta!(DroopOPF, :DocTestSetup, :(using DroopOPF); recursive = true)

# Publication is an allowlist: local planning/history pages and evidence assets
# are never copied into the public build, its search index or direct URLs.
const PUBLIC_PAGES = [
        "Home" => "index.md",
        "Learn DroopOPF" => [
            "Installation and learning paths" => "getting_started.md",
            "What problem are we solving?" => "concepts.md",
            "Your first OPF" => "first_opf.md",
            "Your first security study" => "first_security.md",
            "Read a Volt/VAR curve" => "volt_var.md",
            "AC physics and schematics" => "ac_model.md",
            "Outages, demands and periods" => "study_workflows.md",
            "Notation, signs and units" => "notation.md",
        ],
        "Model and solve" => [
            "Data model reference" => "data_model.md",
            "Case import and export" => "case_io.md",
            "PSS/E import and saved solutions" => "psse.md",
            "Solver formulations" => "solvers.md",
            "SCOPF policies and API" => "scopf.md",
            "Droop parameter design" => "droop_optimization.md",
            "Design with contingency addition" => "droop_security.md",
            "Multi-period design" => "multi_period.md",
            "Mixed AVR / droop" => "mixed_avr_droop.md",
            "Equipment optimization" => "equipment_optimization.md",
        ],
        "Check and interpret" => [
            "Validate an operating point" => "validation.md",
            "Feasibility qualification" => "feasibility_gate.md",
            "Global certificates" => "global_feasibility.md",
            "Robustness and repeated starts" => "robustness.md",
        ],
        "Supported scope" => "release_scope.md",
        "Reference" => [
            "API" => "api.md",
            "Development" => "development.md",
        ],
    ]

function page_files(items)
    files = String[]
    for item in items
        value = last(item)
        value isa AbstractString ? push!(files, value) : append!(files, page_files(value))
    end
    return files
end

mktempdir() do public_source
    for name in page_files(PUBLIC_PAGES)
        original = joinpath(@__DIR__, "src", name)
        destination = joinpath(public_source, name)
        mkpath(dirname(destination))
        edit_url = "https://github.com/frederikgeth/DroopOPF.jl/blob/main/docs/src/" * name
        open(destination, "w") do io
            println(io, "```@meta")
            println(io, "EditURL = ", repr(edit_url))
            println(io, "```")
            println(io)
            write(io, read(original, String))
        end
    end
    mkpath(joinpath(public_source, "assets"))
    cp(joinpath(@__DIR__, "src", "assets", "teaching"), joinpath(public_source, "assets", "teaching"))
    cp(joinpath(@__DIR__, "src", "assets", "teaching.css"), joinpath(public_source, "assets", "teaching.css"))
    makedocs(
        root = @__DIR__,
        source = public_source,
        clean = true,
        pagesonly = true,
        sitename = "DroopOPF.jl",
        authors = "DroopOPF contributors",
        modules = [DroopOPF],
        repo = "https://github.com/frederikgeth/DroopOPF.jl/blob/{commit}{path}#L{line}",
        format = Documenter.HTML(
            prettyurls = get(ENV, "CI", "false") == "true",
            canonical = "https://frederikgeth.github.io/DroopOPF.jl",
            repolink = "https://github.com/frederikgeth/DroopOPF.jl",
            edit_link = "main",
            assets = ["assets/teaching.css"],
        ),
        pages = PUBLIC_PAGES,
        checkdocs = :exports,
    )
end

if get(ENV, "DOCUMENTER_DEPLOY", "false") == "true"
    deploydocs(
        repo = "github.com/frederikgeth/DroopOPF.jl.git",
        devbranch = "main",
        # Stable is an explicitly promoted documentation snapshot.
        versions = ["stable" => "docs-2026-11-01", "v#.#", "dev" => "dev"],
        push_preview = true,
    )
end
