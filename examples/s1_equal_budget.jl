include("s1_public_recovery.jl")
function s1_equal_budget(out)
    source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case300_ieee.m")
    original=load_matpower_case(source;base_frequency=60.)
    anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public300-baseline-design.json"))
    case,p,_=s1_public_overlay(original,anchor,source;bank_count=32)
    case=s1_load(case,1.05)
    row,result=s1_attempt(out,"public300-load1.05-uninterrupted",case,anchor.opf.state;policies=p,
        options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"max_iter"=>2000,"max_cpu_time"=>120.),
        tags=Dict("study"=>"equal_total_budget","load_factor"=>1.05,
            "comparison"=>"1000+1000 iterations and 60+60 CPU seconds for source plus one restart"))
    get(row,"physical_valid",false) && (row["source_audit"]=s1_source_audit(case,result,source))
    s1_summary(out,[row])
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_equal_budget(abspath(ARGS[1]))
