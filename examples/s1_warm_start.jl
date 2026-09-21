# Experimental same-formulation restart state. Not a public core API.
function s1_seed_layout(model,context)
    nl=all_nonlinear_constraints(model);nlset=Set(nl)
    regular=[c for c in all_constraints(model;include_variable_in_set_constraints=true) if !(c in nlset)]
    signature=bytes2hex(sha256(join(vcat([context,string(objective_sense(model)),string(objective_function(model))],
        name.(all_variables(model)),string.(regular),string.(nl)),"\n")))
    (variables=all_variables(model),regular=regular,nonlinear=nl,signature=signature)
end
function s1_capture_seed(model,context)
    has_values(model) && has_duals(model) || throw(ArgumentError("restart requires primal and dual values"))
    layout=s1_seed_layout(model,context)
    primal=value.(layout.variables);regular=dual.(layout.regular);nonlinear=dual.(layout.nonlinear)
    all(isfinite,vcat(primal,regular,nonlinear)) || throw(ArgumentError("nonfinite restart state"))
    Dict("schema_version"=>1,"context"=>context,"signature"=>layout.signature,
        "primal"=>primal,"regular_dual"=>regular,"nonlinear_dual"=>nonlinear,
        "source_status"=>string(termination_status(model)),
        "dual_convention"=>"JuMP/MOI constraint duals, including variable bounds; no manual sign conversion")
end
function s1_apply_seed!(model,seed,context;mode=:primal)
    mode in (:primal,:zero_dual,:primal_dual) || throw(ArgumentError("unknown restart mode"))
    layout=s1_seed_layout(model,context)
    seed["schema_version"]==1 && seed["context"]==context && seed["signature"]==layout.signature ||
        throw(ArgumentError("restart model/context mismatch"))
    # Validate all arrays before modifying the model, even for a primal-only restart.
    for (key,refs) in (("primal",layout.variables),("regular_dual",layout.regular),("nonlinear_dual",layout.nonlinear))
        length(seed[key])==length(refs) && all(isfinite,seed[key]) || throw(ArgumentError("invalid restart array: $key"))
    end
    for (x,v) in zip(layout.variables,seed["primal"])
        set_start_value(x,v)
    end
    if mode!=:primal
        for (c,v) in zip(layout.regular,seed["regular_dual"])
            set_dual_start_value(c,mode==:zero_dual ? 0. : v)
        end
        set_nonlinear_dual_start_value(model,mode==:zero_dual ? zeros(length(layout.nonlinear)) : Float64.(seed["nonlinear_dual"]))
    end
    (primal=length(layout.variables),regular_dual=mode==:primal ? 0 : length(layout.regular),
        nonlinear_dual=mode==:primal ? 0 : length(layout.nonlinear))
end
