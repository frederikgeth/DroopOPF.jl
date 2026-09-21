include("s1_public_recovery.jl")
"""Localize historical failures without modifying their original solver evidence."""
function s1_audit_retained(out)
    mkpath(out);rows=[]
    source_out=joinpath(@__DIR__,"..","artifacts","s1_public_controls")
    evidence=JSON.parsefile(joinpath(source_out,"summary.json"))
    for n in (118,300)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(source_out,"public$n-baseline-design.json"))
        overlay,_,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        for row in evidence
            row["buses"]==n || continue
            result=read_joint_design(joinpath(source_out,row["name"]*"-design.json"))
            case=occursin("baseline",row["name"]) ? original : s1_load(overlay,get(row["tags"],"load_factor",1.))
            check=validate_joint_design(case,result)
            details=isnothing(check.physical) ? nothing : s1_failure_details(with_joint_settings(case,result),result.opf.state)
            if !isnothing(details)
                Set(Symbol(d["category"]) for d in details)==Set(check.physical.violations) || error("failure category mismatch: $(row["name"])")
            end
            push!(rows,Dict("name"=>row["name"],"physical_check_status"=>isnothing(details) ? "not_evaluated" : "evaluated",
                "physical_failures"=>details,"valid"=>check.valid))
        end
    end
    write(joinpath(out,"retained-public-failures.json"),JSON.json(rows;pretty=true))
    println("Audited $(length(rows)) retained attempts; localized categories agree with independent validator.")
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_audit_retained(abspath(ARGS[1]))
