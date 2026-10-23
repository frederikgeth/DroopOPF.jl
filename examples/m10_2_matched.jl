# M10.2 base-case comparisons only. No SCOPF solve is called.
using DroopOPF, JSON, SHA
const ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT = abspath(ARGS[1])
const SOURCE = joinpath(ROOT,"artifacts","m7_3")
const FACTORS = [0.95,0.975,1.0,1.025,1.05]
const TAGS = [string(t,s,d) for t in 0:1 for s in 0:1 for d in 0:1]
const ATTRS = Dict{String,Any}("tol"=>1e-9,"acceptable_tol"=>1e-9,
    "bound_relax_factor"=>0.,"max_iter"=>500,"max_cpu_time"=>20.)
json(path,x)=open(io->JSON.print(io,DroopOPF._json_data(x),2),path,"w")
sha(path)=bytes2hex(sha256(read(path)))
mkpath(joinpath(OUT,"cases")); mkpath(joinpath(OUT,"attempts"))
# Bind the protocol before any numerical work; refuse to overwrite a prior run.
isfile(joinpath(OUT,"protocol.json")) && error("Use a new output directory for a new run")
sources = [joinpath(SOURCE,"input-study.json"),joinpath(SOURCE,"evidence.json")]
append!(sources,[joinpath(SOURCE,"design-$tag-$run.json") for tag in TAGS for run in 1:2])
code=[joinpath(ROOT,"Project.toml"),joinpath(ROOT,"Manifest.toml"),@__FILE__,
    joinpath(ROOT,"examples","report_m10_2_matched.py")]
append!(code,[joinpath(ROOT,"src",p) for p in readdir(joinpath(ROOT,"src")) if endswith(p,".jl")])
json(joinpath(OUT,"protocol.json"),Dict("date"=>"2026-10-18","scope"=>"synthetic three-bus base-case OPF; no SCOPF",
    "tags"=>TAGS,"factors"=>FACTORS,"nominal_factor"=>1.,"heldout_factors"=>filter(!=(1.),FACTORS),
    "objective"=>"sum((Pg-Pg_initial)^2) + 0.001 sum((Qg-Qg_initial)^2); zero design penalty; losses are metrics",
    "equipment_policy"=>"all tap, bank and droop design settings frozen to selected historical nominal design; only operating state optimized",
    "starts"=>"two saved nominal states of each configuration; no held-out tuning or demand continuation",
    "mode_comparison"=>"111 equipment; droop reused from frozen grid; FixedQ and AVR targets calibrated once from selected nominal state; FreeQ within same Q limits",
    "mode_design_claim"=>"generator local AVR comparison only; transformer AVR and target co-design excluded",
    "expected_groups"=>55,"expected_new_opf_attempts"=>110,"saved_nominal_replays"=>16,
    "acceptance"=>"at least one native-success physically valid attempt per group; all sixteen nominal designs replay valid; independent replay agrees",
    "tolerances"=>Dict("power"=>1e-6,"control"=>1e-5,"limits"=>1e-6,"objective"=>1e-8),
    "smooth_epsilon"=>1e-5,"optimizer"=>"Ipopt","optimizer_attributes"=>ATTRS,
    "source_hashes"=>Dict(relpath(p,ROOT)=>sha(p) for p in sources),
    "code_environment_hashes"=>Dict(relpath(p,ROOT)=>sha(p) for p in code),"julia_version"=>string(VERSION)))
case=read_study(joinpath(SOURCE,"input-study.json")).case
saved=[]; selected=Dict(); designs=Dict()
for tag in TAGS
    candidates=[]
    for run in 1:2
        path=joinpath(SOURCE,"design-$tag-$run.json")
        result=read_joint_design(path); designs[(tag,run)]=result
        check=validate_joint_design(case,result)
        row=Dict("tag"=>tag,"run"=>run,"source"=>relpath(path,ROOT),"validation"=>check,
            "result"=>DroopOPF._json_data(result.opf),"metrics"=>joint_design_metrics(case,result),
            "physical_case"=>with_joint_settings(case,result),"valid"=>check.valid)
        push!(saved,row); check.valid && push!(candidates,row)
    end
    isempty(candidates) && error("No replay-valid source design: $tag")
    selected[tag]=candidates[argmin([r["result"]["objective"] for r in candidates])]
end
json(joinpath(OUT,"nominal_replay.json"),saved)
all(r["valid"] for r in saved) || error("Source design replay failed; do not launch evaluations")
rows=[]
function scaled(c,f)
    Case(c.id; base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,
        loads=[Load(l.id,l.bus_id;p=l.p*f,q=l.q*f) for l in c.loads],
        generators=c.generators,controls=c.controls,attachments=c.attachments)
end
function assignments(c,mode,nominal)
    mode=="droop" && return nothing
    [mode=="free_q" ? ReactiveControlAssignment(g.id,FreeQ()) :
        mode=="fixed_q" ? ReactiveControlAssignment(g.id,FixedQ(nominal.qg[i])) :
        ReactiveControlAssignment(g.id,AVR(nominal.vm[findfirst(b->b.id==g.bus_id,c.network.buses)]),
            RegulatedLocation(:bus,g.bus_id)) for (i,g) in enumerate(c.generators)]
end
for mode in ("droop","fixed_q","free_q","avr")
    for tag in (mode=="droop" ? TAGS : ["111"])
        pick=selected[tag]; design=designs[(tag,pick["run"])]; frozen=with_joint_settings(case,design)
        reactive=assignments(frozen,mode,design.opf.state)
        for factor in FACTORS
            c=scaled(frozen,factor); key="$tag-$mode-$factor"
            write_study(joinpath(OUT,"cases","$key.json"),Study(c;reactive_assignments=reactive))
            for run in 1:2
                row=Dict{String,Any}("group"=>key,"tag"=>tag,"mode"=>mode,"factor"=>factor,"start"=>run,
                    "selected_source_run"=>pick["run"],"valid"=>false,
                    "case_file"=>"cases/$key.json","attempt_file"=>"attempts/$key-$run.json")
                try
                    r=solve_opf(c;initial_state=designs[(tag,run)].opf.state,smooth_epsilon=1e-5,
                        optimizer_attributes=ATTRS,reactive_assignments=reactive)
                    v=validate_equilibrium(c,r;reactive_assignments=reactive)
                    native=r.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
                    merge!(row,Dict("result"=>r,"validation"=>v,"native_success"=>native,"valid"=>native&&v.valid))
                    if !isnothing(r.state)
                        s=r.state; fl=branch_flows(c.network,s)
                        row["metrics"]=Dict("branch_loss_pu"=>real(sum(fl.from)+sum(fl.to)),
                            "shunt_consumption_pu"=>real(sum(shunt_powers(c.network,s))+sum(bank_powers(c.network,s))),
                            "objective_recomputed"=>sum((s.pg[i]-g.initial_p)^2+0.001*(s.qg[i]-g.initial_q)^2 for (i,g) in enumerate(c.generators)),
                            "q_effort_pu"=>sum(abs,s.qg),
                            "avr_target_error_pu"=>mode=="avr" ? maximum(abs(s.vm[findfirst(b->b.id==g.bus_id,c.network.buses)]-reactive[i].mode.voltage_setpoint) for (i,g) in enumerate(c.generators)) : nothing,
                            "q_limit_exposure"=>count(i->min(s.qg[i]-c.generators[i].q_min,c.generators[i].q_max-s.qg[i])<=1e-6,eachindex(s.qg)))
                    end
                catch err
                    row["error"]=sprint(showerror,err)
                end
                json(joinpath(OUT,row["attempt_file"]),row);push!(rows,row)
                println(key," start ",run," valid=",row["valid"]);flush(stdout)
            end
        end
    end
end
json(joinpath(OUT,"attempts.json"),rows)
println("Completed ",length(rows)," attempts; report independently before acceptance")
