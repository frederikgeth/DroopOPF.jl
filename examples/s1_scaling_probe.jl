include("s1_public_recovery.jl")
function s1_scaling_probe(out)
    mkpath(out);rows=[]
    for n in (118,300),factor in (1.,1.05)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
        case,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        case=s1_load(case,factor)
        # Same state, settings, smoothing, objective, tolerances and budget for all three arms.
        for (label,scaling) in (("default",Dict{String,Any}()),
            ("none",Dict{String,Any}("nlp_scaling_method"=>"none")),
            ("gradient1",Dict{String,Any}("nlp_scaling_method"=>"gradient-based","nlp_scaling_max_gradient"=>1.)))
            options=merge(Dict{String,Any}("bound_push"=>1e-8,"bound_frac"=>1e-8),scaling)
            row,result=s1_attempt(out,"public$n-load$factor-$label",case,anchor.opf.state;
                policies=p,solver=:ipopt,epsilon=1e-6,options,
                tags=Dict("study"=>"matched_scaling","load_factor"=>factor,"scaling"=>label))
            get(row,"physical_valid",false) && (row["source_audit"]=s1_source_audit(case,result,source))
            push!(rows,row);s1_summary(out,rows)
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_scaling_probe(abspath(ARGS[1]))
