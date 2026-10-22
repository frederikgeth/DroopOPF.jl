# Solve the already source-audited outer LP once more to obtain a coordinated
# dispatch start. This point is never an AC feasibility witness.
using DroopOPF,SHA
const JuMP=DroopOPF.JuMP
const JSON=DroopOPF.JSON
using .JuMP
import HiGHS
const SS_ROOT=normpath(joinpath(@__DIR__,".."))

function shared_active_seed(factor)
    folder=joinpath(SS_ROOT,"artifacts/s2_scopf/ieee500_native/emergency_loadability/shared_active_bound/factor-$factor")
    source=joinpath(folder,"result.json");r=JSON.parsefile(source);q=DroopOPF._flp_parse
    audit=JSON.parsefile(joinpath(folder,"independent_audit.json"))
    @assert audit["verified"] && audit["result_sha256"]==bytes2hex(sha256(read(source)))
    FR=DroopOPF._FR
    bounds=[(q(p[1]),q(p[2])) for p in r["variable_bounds"]]
    rows=[(Dict(parse(Int,i)=>q(a) for(i,a) in row["coefficients"]),q(row["rhs"])) for row in r["rows"]]
    d=DroopOPF._FeasibilityLP(bounds,rows,Int[],Int[],Int[],Int[],Tuple{Int,Int}[],Tuple{Dict{Int,FR},Dict{Int,FR},FR}[])
    m=Model(HiGHS.Optimizer);set_silent(m);set_time_limit_sec(m,90.)
    @variable(m,DroopOPF._flp_round(bounds[i][1],false)<=x[i=1:length(bounds)]<=DroopOPF._flp_round(bounds[i][2],true))
    @objective(m,Min,x[r["total_loss"]])
    refs=[DroopOPF._flp_solver_row!(m,x,d,row) for row in rows]
    timed=@timed optimize!(m);states=Any[];gap=nothing;multipliers=Any[]
    if dual_status(m)==JuMP.MOI.INFEASIBILITY_CERTIFICATE
        multipliers=Any[[i,string(DroopOPF._fq(-v))] for(i,v) in enumerate(dual.(refs)) if v<0]
        gap=DroopOPF._flp_margin(d,multipliers)
    end
    if has_values(m)
        p=value.(x)
        for (k,b) in enumerate(r["blocks"])
            id=k==1 ? "base" : r["events"][k-1]["id"]
            loads=b["case"]["loads"]
            push!(states,(;id,pg=p[b["pg"]],dr=Dict(string(l["id"])=>(k==1 ? 0. : p[b["dr"][i]]) for(i,l) in enumerate(loads)),
                shed=Dict(string(l["id"])=>(k==1 ? 0. : p[b["shed"][i]]) for(i,l) in enumerate(loads)),
                delta=isnothing(b["delta"]) ? nothing : p[b["delta"]]))
        end
    end
    result=(;factor,status=string(termination_status(m)),elapsed_seconds=timed.time,states,multipliers,
        certified_infeasible=!isnothing(gap) && gap>0,gap_exact=isnothing(gap) ? nothing : string(gap),
        model_sha256=bytes2hex(sha256(read(source))),source_adapter_sha256=bytes2hex(sha256(read(@__FILE__))),
        purpose="Numerical start only. No AC feasibility, original-physics optimality or required-relief claim.")
    write(joinpath(folder,"seed.json"),JSON.json(DroopOPF._json_data(result);pretty=true))
    println("SHARED SEED status=",result.status," states=",length(states)," certified=",result.certified_infeasible)
end

abspath(PROGRAM_FILE)==(@__FILE__) && shared_active_seed(parse(Float64,only(ARGS)))
