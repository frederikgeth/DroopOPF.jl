include("s1_ccopt_policy_matrix.jl")

"""Re-solve unsolved IEEE-118 frozen cells from every accepted IEEE-118 state.

States are only transferred within a network size; 118-to-300 transfer is not
meaningful because the voltage and generator state vectors have different
dimensions. A failed recovery remains `unknown`, not an infeasibility claim.
"""
function s1_ccopt_frozen_cross_seed(frozen_out, out)
    frozen=JSON.parsefile(joinpath(frozen_out,"summary.json"))
    source_rows=[r for r in frozen["rows"] if r["case_key"]["buses"]==118 && get(r,"valid",false)]
    isempty(source_rows) && error("no accepted IEEE-118 frozen witness to transfer")
    target_cells=[c for c in s1_ccopt_policy_cells() if c.n==118 && !any(get(r,"name","")=="public$(c.n)-load$(c.load_factor)-ccopt-$(c.start)" && get(r,"valid",false) for r in frozen["rows"])]
    mkpath(out); summary_path=joinpath(out,"summary.json")
    rows=isfile(summary_path) ? [Dict{String,Any}(string(k)=>v for (k,v) in r) for r in JSON.parsefile(summary_path)["rows"]] : Dict{String,Any}[]
    profile=Dict{String,Any}("max_iter"=>1000,"max_wall_time"=>60.,"sigma_min"=>1e-14,"tol"=>1e-11,"acceptable_tol"=>1e-11)
    options=Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),"tol"=>1e-11,"acceptable_tol"=>1e-11)
    for source_row in source_rows, target in target_cells
        source_name=source_row["name"]
        name="$(target.n)-load$(target.load_factor)-$(target.start)-from-$(source_name)"
        any(get(r,"name",nothing)==name for r in rows) && continue
        source_design=read_joint_design(joinpath(frozen_out,source_name*"-design.json"))
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case118_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public118-baseline-design.json"))
        case,policies,_=s1_public_overlay(original,anchor,source;bank_count=12); case=s1_load(case,target.load_factor)
        selected=target.start==:anchor ? policies : s1_reseed(case,policies;fraction=target.start==:flat_low ? .2 : .8)
        tags=Dict{String,Any}("matrix"=>"s1_ccopt_frozen_cross_seed_v1","source_witness"=>source_name,"target_start"=>string(target.start),"target_load_factor"=>target.load_factor,"claim"=>"recovery result is a local witness only; failure is not infeasibility")
        row,result=s1_ccopt_attempt(out,name,case,source_design.opf.state;policies=selected,tags,option_overrides=options)
        row["validated_local_witness"]=get(row,"valid",false)
        row["solution_status"]=get(row,"valid",false) ? "yes: validated local witness" : "unknown: no validated witness from this run"
        push!(rows,row)
        write(summary_path,JSON.json(Dict("schema"=>"s1-ccopt-frozen-cross-seed-v1","profile"=>profile,"rows"=>rows);pretty=true)*"\n")
        println("CROSS SEED ",name," valid=",get(row,"valid",false)); flush(stdout)
    end
    s1_ccopt_cross_seed_report(out,rows)
end

function s1_ccopt_cross_seed_report(out,rows)
    open(joinpath(out,"report.md"),"w") do io
        println(io,"# CCOpt frozen IEEE-118 cross-seed recovery\n")
        println(io,"Each row uses an accepted frozen IEEE-118 solution as its initial state for an originally unsolved IEEE-118 cell. A passed row supplies a validated local witness. A failed row is **not** a conclusion that the target has no solution. IEEE 300 is excluded because its state dimension differs.\n")
        println(io,"| Target from witness | Status | Accepted | Has validated local witness? | Exact droop max |\n|---|---|---:|---|---:|")
        for r in rows
            a=get(r,"exact_droop_audit",Dict{String,Any}()); witness=get(r,"valid",false) ? "yes" : "unknown"
            println(io,"| ",r["name"]," | ",get(r,"status","ERROR")," | ",get(r,"valid",false)," | ",witness," | ",get(a,"max_residual_pu","—")," |")
        end
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_ccopt_frozen_cross_seed(abspath(ARGS[1]),abspath(ARGS[2]))
