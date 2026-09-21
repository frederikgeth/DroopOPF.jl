include("s1_public_recovery.jl")
function s1_public_polish(out)
    mkpath(out);rows=[]
    source_out=joinpath(@__DIR__,"..","artifacts","s1_public_controls")
    evidence=JSON.parsefile(joinpath(source_out,"summary.json"))
    for n in (118,300),factor in (1.,1.05)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(source_out,"public$n-baseline-design.json"))
        case,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        case=s1_load(case,factor)
        candidates=[r for r in evidence if r["buses"]==n && r["valid"] &&
            get(r["tags"],"study","")=="public_joint" && r["tags"]["load_factor"]==factor]
        isempty(candidates) && continue
        selected=candidates[argmin([r["objective"] for r in candidates])]
        seed=read_joint_design(joinpath(source_out,selected["name"]*"-design.json"))
        policies=s1_reseed(case,p;result=seed)
        budget=s1_epsilon_bound(case,p)
        for solver in (:ipopt,:madnlp)
            row,r=s1_attempt(out,"public$n-load$factor-$solver-polish",case,seed.opf.state;policies,solver,
                epsilon=budget.epsilon,options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8),
                tags=Dict("study"=>"polish","load_factor"=>factor,"source_attempt"=>selected["name"],
                    "source_objective"=>selected["objective"],"smoothing_bound"=>budget.max_curve_gap))
            get(row,"physical_valid",false) && (row["source_audit"]=s1_source_audit(case,r,source))
            push!(rows,row);s1_summary(out,rows)
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_public_polish(abspath(ARGS[1]))
