include("s1_public_recovery.jl")
include("s1_warm_start.jl")
function s1_public_warmstarts(out)
    mkpath(out);rows=[];selections=[]
    for n in (118,300),factor in (1.,1.05)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
        case,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        case=s1_load(case,factor)
        context="public$n-load$factor-epsilon1e-6-same-formulation"
        seed=Ref{Any}(nothing)
        options=Dict{String,Any}("bound_push"=>1e-8,"bound_frac"=>1e-8)
        capture=(phase,model)->(phase==:solved && (seed[]=s1_capture_seed(model,context));nothing)
        row,_=s1_attempt(out,"public$n-load$factor-source",case,anchor.opf.state;policies=p,options,
            experiment_hook=capture,tags=Dict("study"=>"warmstart","load_factor"=>factor,"mode"=>"source"))
        push!(rows,row);s1_summary(out,rows)
        isnothing(seed[]) && error("no finite primal/dual seed; source failure retained")
        seedpath=joinpath(out,"public$n-load$factor-seed.json")
        write(seedpath,JSON.json(seed[];pretty=true))
        # Read back so every restart uses the persisted artifact, including failed source iterates.
        saved=JSON.parsefile(seedpath)
        for mode in (:primal,:zero_dual,:primal_dual)
            settings=copy(options)
            if mode!=:primal
                merge!(settings,Dict("warm_start_init_point"=>"yes","warm_start_bound_push"=>1e-8,
                    "warm_start_bound_frac"=>1e-8,"warm_start_slack_bound_push"=>1e-8,
                    "warm_start_slack_bound_frac"=>1e-8,"warm_start_mult_bound_push"=>1e-8))
            end
            applied=Ref{Any}(nothing)
            hook=(phase,model)->(phase==:built && (applied[]=s1_apply_seed!(model,saved,context;mode));nothing)
            row,result=s1_attempt(out,"public$n-load$factor-$mode",case,anchor.opf.state;policies=p,options=settings,
                experiment_hook=hook,tags=Dict("study"=>"warmstart","load_factor"=>factor,"mode"=>string(mode),
                    "source_attempt"=>"public$n-load$factor-source","source_status"=>saved["source_status"],
                    "seed_file"=>basename(seedpath),"builder_start_overridden"=>true))
            row["applied_seed_counts"]=applied[]
            startpath=joinpath(out,row["name"]*"-start.json")
            startdata=JSON.parsefile(startpath)
            startdata["start_role"]="builder defaults overridden by the persisted primal seed"
            startdata["seed_file"]=basename(seedpath)
            write(startpath,JSON.json(startdata;pretty=true))
            get(row,"physical_valid",false) && (row["source_audit"]=s1_source_audit(case,result,source))
            write(joinpath(out,row["name"]*"-diagnostics.json"),JSON.json(row;pretty=true))
            push!(rows,row);s1_summary(out,rows)
        end
        # Declared selection rule: lowest objective among fully validated attempts only.
        group=rows[end-3:end];eligible=[r for r in group if r["valid"]]
        selected=isempty(eligible) ? nothing : eligible[argmin([r["objective"] for r in eligible])]["name"]
        push!(selections,Dict("buses"=>n,"load_factor"=>factor,"selected"=>selected,
            "attempts"=>[r["name"] for r in group],"rule"=>"minimum objective among independently validated attempts; otherwise unresolved"))
        write(joinpath(out,"selection.json"),JSON.json(selections;pretty=true))
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_public_warmstarts(abspath(ARGS[1]))
