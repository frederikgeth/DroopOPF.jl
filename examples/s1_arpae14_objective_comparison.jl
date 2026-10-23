# Fixed selected controller, identical starts and feasible set; objective changes only.
include("s1_arpae14_droop_design.jl")
const OC_OUT=joinpath(GATED_ROOT,"artifacts/s1_arpae14_objective_comparison")
const OC_COST_SCALE=1e5
function oc_costs()
    path=joinpath(GATED_ROOT,"test/data/arpae/c1_network01/results/scenario_01_pmin0_qsym/network_model.json")
    raw=JSON.parsefile(path);lines=Dict{Int,Vector{Tuple{Float64,Float64}}}()
    for (id,g) in raw["gen"]
        g["gen_status"]==1 || continue
        @assert g["model"]==1
        v=g["cost"];segments=Tuple{Float64,Float64}[]
        for i in 1:g["ncost"]-1
            x1,y1,x2,y2=Float64.(v[2i-1:2i+2]);@assert x2>x1
            m=(y2-y1)/(x2-x1);push!(segments,(m,y1-m*x1))
        end
        @assert issorted(first.(segments))
        lines[parse(Int,id)]=segments
    end
    lines,path
end
oc_cost(c,s,costs)=sum(maximum(m*s.pg[i]+b for (m,b) in costs[g.id]) for (i,g) in enumerate(c.generators) if g.available)
function oc_metrics!(c,r,costs,objective)
    haskey(r,"state") || return
    s=eq_state(r["state"])
    r["dispatch_deviation"]=sum((s.pg[i]-g.initial_p)^2+.001*(s.qg[i]-g.initial_q)^2 for (i,g) in enumerate(c.generators))
    r["economic_cost"]=oc_cost(c,s,costs)
    r["loss_mw"]=(sum(s.pg)-sum(l.p for l in c.loads))*c.base_power
    expected=objective=="dispatch" ? r["dispatch_deviation"] : objective=="loss" ? r["loss_mw"]/c.base_power : r["economic_cost"]/OC_COST_SCALE
    r["objective_recomputed"]=expected;r["objective_replay_error"]=abs(expected-r["objective"])
    if r["accepted"];@assert isapprox(expected,r["objective"];atol=1e-5,rtol=1e-6);end
end
function oc_hook(c,start,costs,objective)
    function hook(phase,model)
        phase==:built || return
        pg=[variable_by_name(model,"pg[$i]") for i in eachindex(c.generators)]
        if objective=="loss"
            pd=sum(l.p for l in c.loads)
            @objective(model,Min,sum(pg)-pd)
        elseif objective=="cost"
            zs=[]
            for (i,g) in enumerate(c.generators)
                g.available || continue
                z=@variable(model,base_name="economic_cost_$(g.id)")
                set_start_value(z,maximum(m*start.pg[i]+b for (m,b) in costs[g.id])/OC_COST_SCALE)
                for (m,b) in costs[g.id];@constraint(model,z>=(m*pg[i]+b)/OC_COST_SCALE);end
                push!(zs,z)
            end
            @objective(model,Min,sum(zs))
        end
    end
end
function run_objective_comparison()
    mkpath(OC_OUT);base=read_study(joinpath(EQ_OUT,"baseline-study.json")).case;source,_,angles,_=gated_inputs();costs,path=oc_costs()
    write_study(joinpath(OC_OUT,"baseline-study.json"),Study(base))
    seeds=Dict();checks=[]
    for f in (.9,.95,1.,1.05,1.1),objective in ("cost","loss")
        s,seedpath=dd_seed(source,objective,f);c=DroopOPF._feasibility_scaled_case(source,f)
        a=validate_feasibility_witness(FeasibilityProblem(c;angle_limits=angles),FeasibilityWitness(s));@assert a["valid"]
        cost=oc_cost(c,s,costs);native=JSON.parsefile(seedpath)["objective"]
        expected=objective=="cost" ? cost : sum(s.pg)-sum(l.p for l in c.loads)
        @assert isapprox(expected,native;atol=objective=="cost" ? 0.01 : 1e-6,rtol=1e-6)
        seeds[(objective,f)]=s;push!(checks,Dict("factor"=>f,"objective"=>objective,"valid"=>true,"objective_replay_error"=>abs(expected-native),"seed_sha256"=>bytes2hex(sha256(read(seedpath)))))
    end
    write(joinpath(OC_OUT,"precursors.json"),JSON.json(checks;pretty=true))
    write(joinpath(OC_OUT,"protocol.json"),JSON.json(Dict("new_solves"=>60,"reused_dispatch"=>30,"controls"=>"fixed uniform8, fixed original references, no deadband, source taps and shunts","objectives"=>["dispatch","loss","cost"],"cost_model"=>"convex source PWL max-of-segments with endpoint extrapolation matching PowerModels","cost_input_sha256"=>bytes2hex(sha256(read(path))),"cost_scale"=>OC_COST_SCALE,"loss_units"=>"pu active generation minus load","demands"=>[.9,.95,1.,1.05,1.1],"starts"=>["demand matched cost OPF","demand matched loss OPF"],"solvers"=>["ipopt","madnlp","ccopt"],"budget"=>"600 iterations,20 native solver seconds","smooth_voltage_absolute_q"=>1e-6);pretty=true))
    ledger=joinpath(OC_OUT,"rows.jsonl")
    if !isfile(ledger)
        open(ledger,"w") do io
            for line in readlines(joinpath(EQ_OUT,"rows.jsonl"))
                r=JSON.parse(line);r["tags"]["family"]=="fixed" || continue
                r["tags"]["objective"]="dispatch";r["name"]="dispatch-"*r["name"];r["reused_from"]="artifacts/s1_arpae14_equipment/rows.jsonl"
                c=DroopOPF._feasibility_scaled_case(base,r["tags"]["factor"]);eq_details(c,r,angles,eq_policy(c,"fixed"));oc_metrics!(c,r,costs,"dispatch")
                println(io,JSON.json(r))
            end
        end
    end
    rows=[JSON.parse(s) for s in readlines(ledger)];done=Set(r["name"] for r in rows)
    for objective in ("loss","cost"),f in (.9,.95,1.,1.05,1.1),init in ("cost","loss"),solver in (:ipopt,:madnlp,:ccopt)
        name="$objective-$f-$init-$solver";name in done && continue
        c=DroopOPF._feasibility_scaled_case(base,f);s=seeds[(init,f)]
        tags=Dict("family"=>"fixed","objective"=>objective,"factor"=>f,"initialization_objective"=>init)
        r=js_cell(c,s,angles,solver,tags;reactive_epsilon=1e-6,objective_hook=oc_hook(c,s,costs,objective));r["name"]=name
        eq_details(c,r,angles,eq_policy(c,"fixed"));oc_metrics!(c,r,costs,objective)
        open(ledger,"a") do io;println(io,JSON.json(r));end;push!(rows,r)
        println("OBJECTIVE ",length(rows),"/90 ",name," accepted=",r["accepted"]);flush(stdout)
    end
    @assert length(rows)==90
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_objective_comparison()
