include("s1_staged_initialization.jl")
function s1_staged_matrix(out,solver,strategy)
    mkpath(out);rows=[]
    factors=strategy==:load ? (1.05,) : (1.,1.05)
    for n in (118,300),factor in factors,start_kind in (:anchor,:flat_low,:flat_high)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
        base,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        state=start_kind==:anchor ? anchor.opf.state : s1_flat(base)
        controls=start_kind==:anchor ? p : s1_reseed(base,p;fraction=start_kind==:flat_low ? .2 : .8)
        name="public$n-load$factor-$solver-$start_kind-$strategy"
        row,result=s1_run_staged(out,name,base,state;policies=controls,solver,strategy,factor,
            tags=Dict("start"=>string(start_kind)))
        row["valid"] && (row["source_audit"]=s1_source_audit(s1_load(base,factor),result,source))
        push!(rows,row);write(joinpath(out,"summary.json"),JSON.json(rows;pretty=true))
        println("STAGED ",name," valid=",row["valid"]," iterations=",row["iterations"]);flush(stdout)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_staged_matrix(abspath(ARGS[1]),Symbol(ARGS[2]),Symbol(ARGS[3]))
