isdefined(@__MODULE__, :fd_inputs) || include("s1_free_droop.jl")
# The final14-bus reference had matched fixed and tap+shunt comparators only.
# Fill the two missing equipment-only comparators without changing old scorecards.
function fd_equipment_baselines()
    size=14;x=fd_inputs(size)
    for family in ("tap","shunt"),f in FD_FACTORS
        base,design=fd_model(x,"droop_"*family);p=(;fd_equipment(design)...,droop_controls=DroopControl[])
        c=DroopOPF._feasibility_scaled_case(base,f);tags=Dict("stage"=>"equipment_baseline","family"=>family,"factor"=>f);rows=[]
        for init in ("joint","loss","cost"),solver in (:ipopt,:madnlp,:ccopt)
            s=init=="joint" ? a500_state(x.ref["state"]) : x.seeds[(init,f)]
            push!(rows,fd_attempt(size,c,s,p,x,"equipment-$family-$f-$init-$solver",merge(tags,Dict("init"=>init));solver))
        end
        r=deepcopy(x.fixed[f]);r["name"]="incumbent-fixed-$f";r["taps"]=x.ref["taps"];r["susceptances"]=x.ref["susceptances"]
        fd_recover(size,c,p,x,tags,rows,r)
    end
end
function fd_legacy14_recovery()
    x=fd_inputs(14);prior=JSON.parse.(readlines(joinpath(FD_ROOT,"artifacts/s1_arpae14_joint_reference/rows.jsonl")))
    append!(prior,JSON.parse.(readlines(joinpath(FD_ROOT,"artifacts/s1_arpae14_joint_reference/joint_anchor_rows.jsonl"))))
    bad=filter(r->get(r["tags"],"arm","")=="joint_frozen" && get(r["tags"],"range","")=="relative5" && !r["accepted"],prior)
    @assert length(bad)==3
    base=read_study(joinpath(FD_ROOT,"artifacts/s1_arpae14_closeout/frozen-study.json")).case
    p=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
    c=DroopOPF._feasibility_scaled_case(base,.9);r=deepcopy(x.fixed[.9])
    @assert validate_feasibility_witness(FeasibilityProblem(c;angle_limits=x.angles),FeasibilityWitness(a500_state(r["state"])))["valid"]
    fd_save(joinpath(FD_OUT,"14/legacy_failures.json"),bad)
    fd_recover(14,c,p,x,Dict("stage"=>"legacy_fixed","family"=>"fixed","factor"=>.9),bad,r)
end

function fd_legacy14_equality_recovery()
    x=fd_inputs(14);c=DroopOPF._feasibility_scaled_case(x.base,.9)
    taps=[TapControl(b.id;lower=x.ref["taps"][string(b.id)],upper=x.ref["taps"][string(b.id)],initial=x.ref["taps"][string(b.id)],nominal=b.tap_ratio) for b in c.network.branches if b.available && b.kind==:transformer]
    banks=[ShuntControl(b.id;lower=x.ref["susceptances"][string(b.id)],upper=x.ref["susceptances"][string(b.id)],initial=x.ref["susceptances"][string(b.id)]) for b in c.network.banks if b.available]
    p=(tap_controls=taps,shunt_controls=banks,droop_controls=DroopControl[]);r=x.fixed[.9]
    bad=JSON.parsefile(joinpath(FD_OUT,"14/legacy_failures.json"))
    tags=Dict("stage"=>"recovery","target_stage"=>"legacy_fixed","family"=>"fixed","factor"=>.9,"seed"=>r["name"],"failed_attempts"=>[a["name"] for a in bad],"method"=>"original equality-bound equipment representation; small barrier and bound push, expanded budget")
    fd_attempt(14,c,a500_state(r["state"]),p,x,"legacy-equality-0.9-ccopt-conditioned",tags;solver=:ccopt,iterations=3000,seconds=60.,mu=1e-8)
end

if abspath(PROGRAM_FILE)==(@__FILE__);fd_equipment_baselines();fd_legacy14_recovery();fd_legacy14_equality_recovery();end
