# Staged P2-02 study. plan/freeze do not solve OPF or SCOPF.
using DroopOPF,JSON,SHA,LinearAlgebra
include("p2_02_cases.jl")
const P2_ROOT=normpath(joinpath(@__DIR__,".."))
const P2_POLICY=(;loading_threshold=.8,voltage_guard=.02,reactive_guard=.1,ac_risk_guard=true)
const P2_OPTIONS=(;smooth_epsilon=1e-5,optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>5.))
p2save(p,x)=open(io->JSON.print(io,DroopOPF._json_data(x),2),p,"w")
p2hash(p)=bytes2hex(sha256(read(p)))
function p2_code_hashes()
    files=[joinpath(P2_ROOT,"src",p) for p in readdir(joinpath(P2_ROOT,"src")) if endswith(p,".jl")]
    append!(files,[@__FILE__,joinpath(@__DIR__,"p2_02_cases.jl"),joinpath(P2_ROOT,"Project.toml"),joinpath(P2_ROOT,"Manifest.toml")])
    Dict(relpath(p,P2_ROOT)=>p2hash(p) for p in files)
end
function p2_plan(out)
    mkpath(out);isfile(joinpath(out,"plan.json")) && error("Plan already exists")
    inputs=p2_fresh_inputs();mkpath(joinpath(out,"planned_cases"))
    for input in inputs
        write_study(joinpath(out,"planned_cases",input.case.id*".json"),Study(input.case))
    end
    p2save(joinpath(out,"plan.json"),(;inputs,expected_inputs=24,policies=(:legacy,:guarded,:exhaustive),
        repetitions=3,warm_repetitions=(2,3),order="rotate the three policy orders by repetition; no parallel solver process",
        policy=P2_POLICY,options=P2_OPTIONS,
        equipment="all source tap ratios and admittances fixed; no tap/shunt decision variables, no movement, no discrete switching",
        response="shared frozen saturated droop; preventive equal-weight active participation; base held fixed for every outage",
        heldout="7/8-bus new topologies, positive/negative reactive demand, two deadband widths and three slope spans; deadband/proportional base regimes",
        endpoint="all catalog entries accounted; unresolved includes native rejection/error and physical failure; finite sample is not a security certificate",
        performance="median of repetitions 2-3, per-input medians summed; filter cost included; JSON/disk excluded",
        initial_code_hashes=p2_code_hashes()))
end
function p2_freeze(out)
    isfile(joinpath(out,"frozen.json")) && error("Freeze already exists; do not retune after held-out evaluation")
    plan=JSON.parsefile(joinpath(out,"plan.json"));@assert plan["expected_inputs"]==24
    dpath=joinpath(out,"frozen_discovery/RESULTS.json");discovery=JSON.parsefile(dpath)
    @assert discovery["original_false_screens"]==12 && discovery["enhanced_false_screens"]==0
    @assert discovery["guard_sha256"]==p2hash(joinpath(P2_ROOT,"src/droop_screening.jl"))
    files=sort(readdir(joinpath(out,"planned_cases");join=true));@assert length(files)==24
    p2save(joinpath(out,"frozen.json"),(;code_hashes=p2_code_hashes(),plan_sha256=p2hash(joinpath(out,"plan.json")),
        planned_case_hashes=Dict(basename(p)=>p2hash(p) for p in files),discovery_sha256=p2hash(dpath),
        discovery_source="old discovery and previously exposed old held-out inputs are known regression evidence; none is a fresh holdout",
        policy=P2_POLICY,guard="opt-in per-unit Q headroom, bounded 8-step piecewise droop/AC predictor, mandatory exact escalation on regime transitions/uncertainty",
        frozen_before_any_new_heldout_base_or_outage_solve=true))
end
function p2_run(out,authorization)
    authorization=="confirmed-fixed-controls" || error("Fresh fixed-equipment campaign confirmation required")
    frozen=JSON.parsefile(joinpath(out,"frozen.json"));@assert frozen["code_hashes"]==p2_code_hashes()
    @assert frozen["plan_sha256"]==p2hash(joinpath(out,"plan.json"))
    @assert all(p2hash(joinpath(out,"planned_cases",p))==h for (p,h) in frozen["planned_case_hashes"])
    runout=joinpath(out,"heldout");ispath(runout) && error("Held-out run exists; preserve it, do not overwrite")
    mkpath(runout);BLAS.set_num_threads(1)
    p2save(joinpath(runout,"authorization.json"),(;scope="user-confirmed fixed-equipment P2-02 campaign and its necessary retries",
        frozen_sha256=p2hash(joinpath(out,"frozen.json")),julia=string(VERSION),threads=Threads.nthreads(),blas_threads=BLAS.get_num_threads()))
    summaries=[]
    for (input_index,input) in enumerate(p2_fresh_inputs())
        dir=joinpath(runout,input.case.id);mkpath(dir)
        row=Dict{String,Any}("id"=>input.case.id,"input_index"=>input_index,"base_valid"=>false,"attempts"=>[])
        try
            assignments=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,g.bus_id)) for g in input.case.generators]
            anchor=solve_opf(input.case;reactive_assignments=assignments,smooth_epsilon=1e-5,
                optimizer_attributes=Dict("tol"=>1e-8,"max_iter"=>500,"max_cpu_time"=>5.))
            p2save(joinpath(dir,"anchor.json"),anchor)
            !isnothing(anchor.state) && validate_equilibrium(input.case,anchor;reactive_assignments=assignments).valid || error("AVR anchor rejected")
            case=p2_overlay(input.case,anchor.state;width=input.width,voltage_span=input.voltage_span,anchor_regime=input.anchor_regime)
            participation=Dict(g.id=>1. for g in case.generators if g.available)
            write_study(joinpath(dir,"input.json"),Study(case;participation));p2save(joinpath(dir,"base.json"),anchor.state)
            row["base_valid"]=true
            for repetition in 1:3
                order=circshift([:legacy,:guarded,:exhaustive],repetition-1)
                for policy in order
                    phases=Dict{Symbol,Float64}()
                    measured=@timed assess_contingency_pipeline(case,anchor.state;P2_POLICY...,P2_OPTIONS...,participation,
                        droop_response_guard=policy==:guarded,screening_enabled=policy!=:exhaustive,_phase_timings=phases)
                    pipe=measured.value;name="$repetition-$policy.json"
                    p2save(joinpath(dir,name),pipe)
                    push!(row["attempts"],(;repetition,policy,elapsed=measured.time,compile_seconds=hasproperty(measured,:compile_time) ? measured.compile_time : nothing,
                        phases,screened=pipe.checks.screened_count,exact_evaluated=pipe.checks.exact_evaluated_count,
                        complete=pipe.checks.complete,path=name))
                    println(input.case.id," ",repetition," ",policy," screened=",pipe.checks.screened_count);flush(stdout)
                end
            end
        catch error
            error isa InterruptException && rethrow()
            row["error"]=sprint(showerror,error)
        end
        p2save(joinpath(dir,"summary.json"),row);push!(summaries,row)
        p2save(joinpath(runout,"summary.json"),summaries)
    end
    @assert frozen["code_hashes"]==p2_code_hashes()
    p2save(joinpath(runout,"completion.json"),(;inputs=length(summaries),code_unchanged=true,
        frozen_sha256=p2hash(joinpath(out,"frozen.json")),all_attempted=length(summaries)==24))
end
mode=ARGS[1];out=abspath(ARGS[2])
mode=="plan" ? p2_plan(out) : mode=="freeze" ? p2_freeze(out) : mode=="run" ? p2_run(out,length(ARGS)>=3 ? ARGS[3] : "") : error("Expected plan, freeze or run")
