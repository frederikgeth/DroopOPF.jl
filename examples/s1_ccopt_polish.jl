using DroopOPF, JSON
import CCOpt
include("s1_ccopt_placement.jl")

const S1_CCOPT_TOTAL_INNER = 1000
const S1_CCOPT_TOTAL_WALL = 60.0

function s1_ccopt_narrow_droop_failure(row)
    physical=get(row,"physical",nothing)
    !isnothing(physical) && get(row,"solver_valid",false) && get(row,"policy_valid",false) &&
        !get(row,"physical_valid",false) && get(physical,"violations",Any[])==["droop"] &&
        get(physical,"droop_residual_max",Inf)<=2e-5
end

"""Run a normal CCOpt solve, then a tighter polish only for a narrow droop-only miss.

Both stages share the declared cumulative inner-iteration and native wall-time
budget. The polish is experimental and never replaces a valid first-stage
solution with an invalid second-stage result.
"""
function s1_ccopt_polished_attempt(out,name,case,start,policies)
    base=Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),
        "tol"=>1e-11,"acceptable_tol"=>1e-11,
        "max_iter"=>S1_CCOPT_TOTAL_INNER,"max_wall_time"=>S1_CCOPT_TOTAL_WALL)
    first_row,first_result=s1_ccopt_attempt(out,name*"-base",case,start;policies,option_overrides=base,
        tags=Dict("stage"=>"base","policy"=>"shared_budget_polish"))
    result=Dict{String,Any}("name"=>name,"base"=>first_row,"polished"=>nothing,
        "selected_stage"=>"base","valid"=>get(first_row,"valid",false))
    if !s1_ccopt_narrow_droop_failure(first_row) || isnothing(first_result)
        write(joinpath(out,name*"-policy.json"),JSON.json(result;pretty=true)*"\n")
        return result
    end
    d=first_row["ccopt"]
    remaining_inner=max(0,S1_CCOPT_TOTAL_INNER-get(d,"inner_iterations",S1_CCOPT_TOTAL_INNER))
    remaining_wall=max(0.,S1_CCOPT_TOTAL_WALL-get(d,"total_time_seconds",S1_CCOPT_TOTAL_WALL))
    result["remaining_budget"]=Dict("inner_iterations"=>remaining_inner,"wall_seconds"=>remaining_wall)
    if remaining_inner==0 || remaining_wall<=0
        result["polish_skipped"]="no remaining shared budget"
        write(joinpath(out,name*"-policy.json"),JSON.json(result;pretty=true)*"\n")
        return result
    end
    tight=Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-16),
        "tol"=>1e-13,"acceptable_tol"=>1e-13,"max_iter"=>remaining_inner,"max_wall_time"=>remaining_wall)
    warm_policies=s1_reseed(case,policies;result=first_result)
    polish_row,_=s1_ccopt_attempt(out,name*"-polish",case,first_result.opf.state;policies=warm_policies,
        option_overrides=tight,tags=Dict("stage"=>"polish","policy"=>"shared_budget_polish"))
    result["polished"]=polish_row
    if get(polish_row,"valid",false)
        result["selected_stage"]="polish";result["valid"]=true
    end
    write(joinpath(out,name*"-policy.json"),JSON.json(result;pretty=true)*"\n")
    result
end

function s1_ccopt_terminal_polish(out)
    mkpath(out)
    source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case118_ieee.m")
    original=load_matpower_case(source;base_frequency=60.)
    anchor=optimize_joint_design(original;initial_state=s1_flat(original),optimizer_attributes=Dict("max_iter"=>1000,"max_cpu_time"=>60.))
    case,policies,_=s1_public_overlay(original,anchor,source;bank_count=12)
    candidate=s1_ccopt_placement_candidates(case,policies).tap_terminal
    selected=(tap_controls=[TapControl(candidate.id;lower=.95*candidate.tap_ratio,upper=1.05*candidate.tap_ratio,nominal=candidate.tap_ratio)],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
    rows=Any[]
    for mode in (:anchor,:flat_low,:flat_high)
        p=mode==:anchor ? selected : s1_reseed(case,selected;fraction=mode==:flat_low ? .2 : .8)
        s=mode==:anchor ? anchor.opf.state : s1_flat(case)
        push!(rows,s1_ccopt_polished_attempt(out,"terminal-tap-$mode",s1_load(case,1.05),s,p))
    end
    write(joinpath(out,"summary.json"),JSON.json(Dict("scope"=>"experimental shared-budget CCOpt polish", "rows"=>rows);pretty=true)*"\n")
    rows
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_ccopt_terminal_polish(abspath(ARGS[1]))
