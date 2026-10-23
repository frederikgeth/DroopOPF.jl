# Report the exact supplied start; deliberately never calls an optimizer.
include("warm_mixed_avr_corridor.jl")
using JuMP
struct InitialStartDiagnosed <: Exception end
length(ARGS)==1||error("provide reserve campaign root")
const DIAG_ROOT=abspath(ARGS[1])
function diagnose_callback(model)
    point=Dict(v=>(is_fixed(v) ? fix_value(v) : something(start_value(v),0.)) for v in all_variables(model))
    violations=primal_feasibility_report(model,point;atol=1e-8)
    ranked=sort(collect(violations);by=x->-x.second)
    rows=[(;violation=x.second,constraint=first(string(x.first),min(1200,length(string(x.first))))) for x in first(ranked,min(12,length(ranked)))]
    mix_save(joinpath(DIAG_ROOT,"diagnose-complete-start/initial-violations.json"),
        (;optimizer_called=false,maximum_violation=isempty(rows) ? 0. : first(rows).violation,rows))
    for r in rows;println(r);end
end
source=read(joinpath(MIX_ROOT,"src/multi_period_security.jl"),String)
source=source[first(findfirst("function _security_emergency_case",source)):end]
needle="    for (k,v) in optimizer_attributes;set_optimizer_attribute(model,k,v);end"
@assert occursin(needle,source)
source=replace(source,needle=>"    Main.diagnose_callback(model);throw(Main.InitialStartDiagnosed())\n"*needle)
write(joinpath(DIAG_ROOT,"diagnostic-source-only.jl"),source)
include_string(DroopOPF,source,"diagnostic-source-only.jl")
try
    warm_corridor(DIAG_ROOT;output_name="diagnose-complete-start")
catch e
    e isa InitialStartDiagnosed || rethrow()
    println("Initial start inspected; no optimizer called")
end
