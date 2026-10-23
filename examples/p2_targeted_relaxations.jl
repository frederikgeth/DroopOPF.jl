# Targeted diagnostics in a fresh root; sealed studies are read-only inputs.
include("p2_mixed_limit_aware.jl")
const DIAG_PRIOR=joinpath(MIX_ROOT,"artifacts/p2_mixed_limit_aware_20261023")
const DIAG_IDS=[:branch_21,:branch_36,:branch_562]
function diag_seed(id)
    rel=id==:branch_21 ? "resolutions-full-topology/branch_21-full-topology-start" : "resolutions/$(id)-topology-start"
    read_multi_period_security(joinpath(DIAG_PRIOR,rel,"result.json"))
end
function diag_attempt(root,id,mode;factor=1.05,seconds=90.,source=nothing,value=nothing)
    label=string(id)*"-"*mode*"-"*replace(string(factor),"."=>"p")*(isnothing(value) ? "" : "-v"*replace(string(value),"."=>"p"))
    x=p2_inputs(joinpath(root,"preflight-"*label))
    parent=read_multi_period_security(joinpath(DIAG_PRIOR,"p2-base/result.json"))
    t=argmin(abs.([.9,1.,1.05,1.,.9].-factor))
    prior=isnothing(source) ? diag_seed(id) : read_multi_period_security(joinpath(source,"result.json"))
    pt=isnothing(source) ? t : 1
    if mode=="tap05"
        x=merge(x,(;p2_policy=SCOPFControlPolicy(taps=:corrective,shunts=:corrective,
            tap_movement_limits=Dict(k=>2v for (k,v) in x.p2_policy.tap_movement_limits),
            shunt_movement_limits=x.p2_policy.shunt_movement_limits)))
    elseif mode in ("thermal","voltage","rating")
        isnothing(value) && error("explicit relaxation value required")
        candidates=JSON.parsefile(joinpath(root,"relaxation-candidates.json"))["outages"][string(id)]
        doc=JSON.parse(JSON.json(mix_data(Study(x.setup.case;reactive_assignments=x.setup.assignments))))
        case=doc["case"]
        if mode=="thermal"
            ids=Set(c["id"] for c in candidates["thermal_candidates"])
            isempty(ids) && error("no targeted thermal candidates")
            for b in case["network"]["branches"];b["id"] in ids && (b["thermal_limit"]*=1+value);end
        elseif mode=="voltage"
            ids=Set(c["id"] for c in candidates["voltage_candidates"])
            isempty(ids) && error("no targeted voltage candidates")
            for b in case["network"]["buses"]
                if b["id"] in ids;b["v_min"]-=value;b["v_max"]+=value;end
            end
        else
            ids=Set(c["id"] for c in candidates["generator_candidates"])
            isempty(ids) && error("no targeted rating candidates")
            for g in case["generators"];g["id"] in ids && (g["s_rated"]*=1+value);end
        end
        file=joinpath(root,"preflight-"*label,"modified-study.json")
        mix_save(file,(;schema_version=10,kind="DroopOPF.Study",active_response="limit_aware_v1",data=doc))
        x=merge(x,(;setup=merge(x.setup,(;case=read_study(file).case))))
    elseif mode!="original"
        error("unsupported diagnostic mode")
    end
    events=[only(e for e in x.events if e.contingency.id==id)]
    controls=[DroopControl(d.control_id;slope_bounds=d.bounds.slope,v_ref_bounds=d.bounds.v_ref,
        initial=isempty(prior.droops) ? parent.droops[d.control_id] : prior.droops[d.control_id]) for d in x.controls]
    starts=[Dict(:base=>parent.periods[t].states[:base],id=>prior.periods[pt].states[id])]
    eq=[(;taps=parent.periods[t].tap_settings[:base],shunts=parent.periods[t].shunt_settings[:base],
        scenarios=Dict(:base=>(;taps=parent.periods[t].tap_settings[:base],shunts=parent.periods[t].shunt_settings[:base]),
            id=>(;taps=prior.periods[pt].tap_settings[id],shunts=prior.periods[pt].shunt_settings[id])))]
    path=joinpath(root,label)
    mix_save(joinpath(root,"diagnostic-"*label*".json"),(;id,mode,factor,value,
        interpretation="Independent base+outage control redesign diagnostic, not a common five-period/catalogue certificate",
        changed_limits=mode!="original",native_power_balance_required=true,load_relief=false,shared_within_base_and_outage=true))
    result=mix_attempt(x,path,[factor],events;controls,starts,initial_equipment=eq,
        initial_avr_targets=[parent.avr_targets[t]],response=:limit_aware,emergency=false,
        schedule=true,objective_policy=:feasibility,seconds,
        solver_options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
    (;path,result)
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    root=abspath(ARGS[1]);mode=ARGS[2]
    ids=length(ARGS)>=3 ? [Symbol(ARGS[3])] : DIAG_IDS
    value=length(ARGS)>=4 ? parse(Float64,ARGS[4]) : nothing
    for id in ids;diag_attempt(root,id,mode;value);GC.gc();end
end
