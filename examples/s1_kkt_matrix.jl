include("s1_kkt.jl")
function s1_kkt_labels(case)
    labels=Dict{String,Any}[]
    for b in case.network.branches
        b.available || continue
        for terminal in ("from","to")
            push!(labels,Dict("family"=>"thermal_squared","equipment_id"=>b.id,"terminal"=>terminal))
        end
    end
    for b in case.network.buses,component in ("P","Q")
        push!(labels,Dict("family"=>"balance_"*component,"equipment_id"=>b.id))
    end
    for a in case.attachments
        only(g for g in case.generators if g.id==a.generator_id).available || continue
        push!(labels,Dict("family"=>"droop","equipment_id"=>a.generator_id,"control_id"=>a.control_id))
    end
    labels
end
function s1_kkt_matrix(out,solver)
    mkpath(out);rows=[]
    selected=((118,1.,:anchor),(118,1.,:flat_high),(118,1.05,:flat_low),(300,1.,:flat_low),(300,1.05,:anchor))
    write(joinpath(out,"selection.json"),JSON.json(Dict("cases"=>selected,"reason"=>"Declared before runs: accepted anchors, numerical failures, physically feasible rejected termination, and stalled recovery source; diagnostic sample, not reliability validation." );pretty=true))
    for (n,factor,start_kind) in selected
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
        base,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        case=s1_load(base,factor);state=start_kind==:anchor ? anchor.opf.state : s1_flat(case)
        policies=start_kind==:anchor ? p : s1_reseed(case,p;fraction=start_kind==:flat_low ? .2 : .8)
        name="public$n-load$factor-$solver-$start_kind";data=Dict{String,Any}();labels=s1_kkt_labels(case)
        function hook(phase,model)
            phase in (:built,:solved) || return
            try
                scales=haskey(data,"initial") ? [r["scale"] for r in data["initial"]["nonlinear_rows"]] : nothing
                point=s1_kkt_snapshot(model;at_start=phase==:built,row_scales=scales)
                length(labels)==length(point["nonlinear_rows"]) || error("joint constraint layout mismatch")
                for (row,label) in zip(point["nonlinear_rows"],labels);merge!(row,label);end
                data[phase==:built ? "initial" : "final"]=point
            catch err
                data[string(phase)*"_error"]=sprint(showerror,err)
            end
        end
        row,result=s1_attempt(out,name,case,state;policies,solver,epsilon=1e-6,
            options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8),experiment_hook=hook,
            tags=Dict("study"=>"physical_kkt_diagnosis","load_factor"=>factor,"start"=>string(start_kind)))
        write(joinpath(out,name*"-kkt.json"),JSON.json(data;pretty=true))
        row["kkt_file"]=name*"-kkt.json"
        push!(rows,Dict(k=>v for (k,v) in row if k ∉ ("trace","bounds")))
        write(joinpath(out,"summary.json"),JSON.json(rows;pretty=true))
        println("KKT ",name," ",keys(data));flush(stdout)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_kkt_matrix(abspath(ARGS[1]),Symbol(ARGS[2]))
