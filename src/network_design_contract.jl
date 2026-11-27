"""Numerical budgets for the prepared-network workflow; no physical limits are changed."""
const NETWORK_DESIGN_DEFAULTS = (hessian="limited-memory", max_iterations=3000, max_seconds=1200.0,
    initialization_max_iterations=3000, initialization_max_seconds=1200.0)
export NETWORK_DESIGN_DEFAULTS

export NetworkDesignContract, solve_network_design, replay_network_design,
    write_network_contract, read_network_contract, network_contract_digest

"""Prepared, provenance-free numerical contract for the validated PowerModels
dictionary. CSV/RAW reconciliation and capability preparation belong to callers.
The reference dictionary supplies island angle anchors; no Case conversion occurs.
"""
struct NetworkDesignContract
    data::Dict{String,Any}
    source::Dict{String,Any}
    controls::Dict{String,Any}
    regulation::Dict{String,Any}
    equipment::Dict{String,Any}
end
_network_plain(x::AbstractDict)=Dict{String,Any}(string(k)=>_network_plain(v) for (k,v) in x)
_network_plain(x::Union{AbstractVector,Tuple,Set})=Any[_network_plain(v) for v in x]
_network_plain(x::Set)=Any[_network_plain(v) for v in sort!(collect(x);by=string)]
_network_plain(x)=x
function NetworkDesignContract(data,controls,regulation,equipment;reference=data)
    d=_network_plain(data);s=_network_plain(reference);c=_network_plain(controls)
    r=_network_plain(regulation);e=_network_plain(equipment)
    get(d,"per_unit",false)===true||throw(ArgumentError("per-unit network required"))
    d["baseMVA"] isa Real&&isfinite(d["baseMVA"])&&d["baseMVA"]>0||throw(ArgumentError("invalid system base"))
    for table in ("bus","gen","branch","load","shunt")
        haskey(d,table)||throw(ArgumentError("missing network table: $table"))
    end
    Set(keys(s["bus"]))==Set(keys(d["bus"]))||throw(ArgumentError("reference bus identities differ"))
    Set(keys(c))⊆Set(keys(d["gen"]))||throw(ArgumentError("unknown controlled generator"))
    for name in ("free_dispatch","shared_droop_groups","avr_targets","avr_plants","fixed_q","reserve_participants")
        haskey(r,name)||throw(ArgumentError("incomplete regulation contract: $name"))
    end
    haskey(e,"selected")&&haskey(e,"policy")||throw(ArgumentError("incomplete equipment contract"))
    NetworkDesignContract(d,s,c,r,e)
end
function network_contract_document(c::NetworkDesignContract)
    Dict("schema"=>"DroopOPF.NetworkDesignContract.v1","data"=>c.data,
      "reference"=>c.source,"controls"=>c.controls,"regulation"=>c.regulation,"equipment"=>c.equipment,
      "policy"=>Dict("active_response"=>"limit_aware_effective_range",
      "reserve"=>"minimum_symmetric_participating_generator_Q_box_fraction",
      "smoothing"=>"factored_sqrt_epsilon_1e-8","physical_replay_tolerance"=>1e-6,
      "reserve_tolerance"=>1e-8))
end
# Canonical sorted serialization avoids dictionary iteration order in content IDs.
_network_canonical(x::AbstractDict)="{"*join([JSON.json(string(k))*":"*_network_canonical(x[k]) for k in sort!(collect(keys(x));by=string)],",")*"}"
_network_canonical(x::AbstractVector)="["*join(_network_canonical.(x),",")*"]"
_network_canonical(x)=JSON.json(x)
network_contract_digest(c::NetworkDesignContract)=bytes2hex(SHA.sha256(_network_canonical(network_contract_document(c))))
function write_network_contract(path,c::NetworkDesignContract)
    ispath(path)&&throw(ArgumentError("contract destination exists"))
    open(io->JSON.print(io,network_contract_document(c)),path,"w")
end
function read_network_contract(path)
    d=JSON.parsefile(path)
    get(d,"schema",nothing)=="DroopOPF.NetworkDesignContract.v1"||throw(ArgumentError("unknown contract schema"))
    c=NetworkDesignContract(d["data"],d["controls"],d["regulation"],d["equipment"];reference=d["reference"])
    d["policy"]==network_contract_document(c)["policy"]||throw(ArgumentError("changed network control policy"))
    c
end
function solve_network_series end
function replay_network_series end
export solve_network_series, replay_network_series
function solve_network_design end
function replay_network_design end

export write_network_design, read_network_design
function write_network_design(path,result)
    ispath(path)&&throw(ArgumentError("result destination exists"))
    result["schema"] in ("DroopOPF.NetworkDesignResult.v1","DroopOPF.NetworkSeriesResult.v1")||throw(ArgumentError("unknown result schema"))
    open(io->JSON.print(io,result),path,"w")
end
function read_network_design(path,contract;require_valid=true)
    result=JSON.parsefile(path)
    if require_valid
        contract isa NetworkDesignContract ? replay_network_design(contract,result) : replay_network_series(contract,result)
    end
    result
end
