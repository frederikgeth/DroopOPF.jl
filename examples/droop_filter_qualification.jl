include("droop_security_workflow.jl")
include("scopf_filter_qualification.jl")

function droop_filter_qualification(output)
    mkpath(output)
    inputs = [qualification_inputs(:discovery);qualification_inputs(:heldout)]
    frozen = (;loading_threshold=.8,voltage_guard=.02,reactive_guard=.1,ac_risk_guard=true)
    options = (;smooth_epsilon=1e-5,optimizer_attributes=Dict("max_iter"=>500,"max_cpu_time"=>15.,"max_wall_time"=>15.))
    security_json(joinpath(output,"protocol.json"),(;provenance=security_provenance(),
        frozen,options,inputs,overlay="all available generators, base-Q/voltage anchored synthetic droop, 0.003 pu half deadband, slope 0.04/Qrange",
        partition="predeclared 3/5-bus discovery and 4/6-bus held-out; no threshold tuning"))
    rows = Any[]
    for input in inputs
        out = mkpath(joinpath(output,input.case.id))
        try
            anchor = qualification_base(input.case)
            equilibrium_report(input.case,anchor).valid || error("AVR anchor rejected")
            case = security_droop_overlay(input.case,anchor.state)
            study = Study(case;participation=Dict(g.id=>1. for g in case.generators if g.available))
            write_study(joinpath(out,"input.json"),study)
            security_json(joinpath(out,"base.json"),anchor.state)
            elapsed = @elapsed comparison = validate_contingency_filter(case,anchor.state;frozen...,options...)
            security_json(joinpath(out,"comparison.json"),comparison)
            regimes = Dict{Symbol,Int}()
            accepted_regimes = Dict{Symbol,Int}()
            for a in comparison.exact.assessments
                isnothing(a.exact_assessment) && continue
                exact = a.exact_assessment
                scenario = scenario_case(case,a.entry.contingency)
                state = exact.result.states[a.entry.contingency.id]
                isnothing(state) && continue
                for point in droop_operating_points(scenario,state)
                    regimes[point.regime] = get(regimes,point.regime,0)+1
                    exact.report.valid && (accepted_regimes[point.regime] = get(accepted_regimes,point.regime,0)+1)
                end
            end
            # Save representative failures as full input/output plot bundles.
            bad = [a for a in comparison.exact.assessments if !isnothing(a.exact_assessment) && !a.exact_assessment.report.valid]
            if !isempty(bad)
                a = first(bad)
                directory = mkpath(joinpath(out,"failure"))
                single = DroopOPF._copy_study(study;contingencies=[a.entry.contingency])
                write_scopf_evaluation_report(joinpath(directory,"evaluation.md"),single,a.exact_assessment.result;
                    context="Retained unresolved droop contingency; never treated as proof of infeasibility.")
            end
            push!(rows,(;id=case.id,split=input.split,buses=length(case.network.buses),valid_base=true,
                elapsed,families=comparison.families,regimes,accepted_regimes,error=nothing))
        catch error
            error isa InterruptException && rethrow()
            push!(rows,(;id=input.case.id,split=input.split,buses=length(input.case.network.buses),
                valid_base=false,error=sprint(showerror,error)))
        end
        security_json(joinpath(output,"results.json"),(;frozen,options,rows,provenance=security_provenance()))
        println("qualification $(input.case.id): $(last(rows))");flush(stdout)
    end
    lines = ["# Filtering under actual droop response", "",
        "The frozen production thresholds were evaluated without retuning on 12 discovery and 12 held-out inputs. Every controlled generator obeys its saturated Volt–VAr curve after outages; unavailability disables that curve. Anchor construction uses AVR only to define synthetic reference settings.", "",
        "| Partition | Family | Outages | Screened | Unresolved | Missed unresolved | Missed physical failures |",
        "|---|---|---:|---:|---:|---:|---:|"]
    for split in (:discovery,:heldout), family in (:line,:transformer,:generator)
        selected = [f for row in rows if row.split==split && row.valid_base for f in row.families if f.device_kind==family]
        total(k)=sum(getproperty(f,k) for f in selected;init=0)
        push!(lines,"| $split | $family | $(total(:total)) | $(total(:screened)) | $(total(:unresolved)) | $(total(:screened_unresolved)) | $(total(:screened_physical_failures)) |")
    end
    append!(lines,["", "![Filtering outcomes](coverage.png)", "", "![Accepted control regimes](regimes.png)", "",
        "Invalid/rejected input count: $(count(r->!r.valid_base,rows)). These inputs remain in results.json and are excluded from outage denominators, not silently counted as passes.",
        "Solver rejection, physical failure and exceptions all count as unresolved. Recall is undefined for families with no unresolved cases. Zero observed misses is limited to these inputs. Timings include first-use compilation and are not a speedup claim.", "",
        "Per-input comparison.json retains exact states, decisions and validation. The iterative design driver always audits screened outages before acceptance, regardless of this filter scorecard."])
    write(joinpath(output,"report.md"),join(lines,"\n")*"\n")
    rows
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && droop_filter_qualification(abspath(ARGS[1]))
