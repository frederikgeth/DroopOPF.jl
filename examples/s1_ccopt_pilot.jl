using DroopOPF, JSON
import CCOpt
include("m7_2_case.jl")
include("s1_experiments.jl")

function s1_ccopt_attempt(out,name,case,start;policies=NamedTuple(),tags=Dict{String,Any}(),
    option_overrides=Dict{String,Any}())
    mkpath(out); diagnostic=Ref{Any}(nothing); encoding_audit=Ref{Any}(nothing)
    options=merge(m5_ccopt_options(),Dict{String,Any}("max_iter"=>1000,"max_wall_time"=>60.),option_overrides)
    row=Dict{String,Any}("name"=>name,"backend"=>"ccopt","encoding"=>"complementarity",
        "valid"=>false,"budget"=>Dict("inner_iterations"=>1000,"wall_seconds"=>60.,
        "outer_iterations"=>nothing,"note"=>"CCOpt does not expose a separate outer-homotopy budget/count through MOI"),
        "tags"=>tags)
    result=nothing
    try
        measured=@timed optimize_joint_design(case;policies...,encoding=:complementarity,
            initial_state=start,optimizer_attributes=options,
            _measurement_hook=(phase,model)->phase==:solved && begin
                diagnostic[]=ccopt_diagnostics(model)
                encoding_audit[]=ccopt_encoding_audit(model)
            end)
        result=measured.value;check=validate_joint_design(case,result)
        exact_audit=exact_droop_audit(case,result)
        write_joint_design(joinpath(out,name*"-design.json"),result)
        merge!(row,Dict("status"=>string(result.opf.termination_status),"valid"=>check.valid,
            "solver_valid"=>check.solver_valid,"policy_valid"=>check.policy_valid,
            "physical_valid"=>!isnothing(check.physical) && check.physical.valid,
            "objective"=>isfinite(result.opf.objective) ? result.opf.objective : nothing,
            "complementarity_residual"=>result.complementarity_residual_max,
            "physical"=>isnothing(check.physical) ? nothing : DroopOPF._json_data(check.physical),
            "exact_droop_audit"=>exact_audit,
            "ccopt"=>diagnostic[],"ccopt_encoding_audit"=>encoding_audit[],"elapsed_seconds"=>measured.time,
            "julia_allocated_bytes"=>measured.bytes))
    catch err
        row["error"]=sprint(showerror,err)
    end
    write(joinpath(out,name*"-diagnostics.json"),JSON.json(row;pretty=true)*"\n")
    println(name,": ",get(row,"status",get(row,"error","unknown"))," valid=",row["valid"]);flush(stdout)
    row,result
end
