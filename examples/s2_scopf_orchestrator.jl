# Process-isolated, resumable S2 qualification runner.
#
# Usage:
#   julia --project=. examples/s2_scopf_orchestrator.jl 300 ipopt [OUT] [WALL_SECONDS]
#
# Existing valid stage artifacts are retained. Each missing stage runs in a
# fresh Julia process. The parent enforces a real wall clock even when a solver
# is blocked in factorization and does not observe its internal CPU limit.
using JSON
using Dates

const STAGES = (:direct,:fixed_seed,:staged,:immediate,:settled,:assessment)
const RECOVERY_STAGES = (:fixed_direct_seed,:staged_direct_seed)
const HOMOTOPY_STAGES = (:fixed_line_homotopy,:fixed_full_homotopy,:staged_homotopy)
const GENERATOR_HOMOTOPY_STAGES = (:fixed_generator_homotopy,
    :fixed_full_generator_first,:staged_generator_first)
const DIRECT_RESPONSE_STAGES = (:direct_immediate,:direct_settled,:direct_assessment)
const RESTORATION_STAGES = (:phase1_fixed,:phase1_strict)
const OUTPUTS = Dict(
    :direct=>"direct-result.json",
    :fixed_seed=>"fixed-result.json",
    :staged=>"staged-result.json",
    :immediate=>"immediate-result.json",
    :settled=>"settled-result.json",
    :assessment=>"stages.json",
    :fixed_direct_seed=>"fixed-direct-seed-result.json",
    :staged_direct_seed=>"staged-direct-seed-result.json",
    :fixed_line_homotopy=>"fixed-line-homotopy-result.json",
    :fixed_full_homotopy=>"fixed-full-homotopy-result.json",
    :staged_homotopy=>"staged-homotopy-result.json",
    :fixed_generator_homotopy=>"fixed-generator-homotopy-result.json",
    :fixed_full_generator_first=>"fixed-full-generator-first-result.json",
    :staged_generator_first=>"staged-generator-first-result.json",
    :direct_immediate=>"direct-immediate-result.json",
    :direct_settled=>"direct-settled-result.json",
    :direct_assessment=>"direct-stages.json",
    :phase1_fixed=>"phase1-fixed.json",
    :phase1_strict=>"phase1-strict-result.json",
)

function write_json(path,data)
    open(path,"w") do io
        JSON.json(io,data;pretty=true)
        println(io)
    end
end

function artifact_present(out,stage)
    isfile(joinpath(out,OUTPUTS[stage]))
end

function report_valid(out,stage)
    prefix=stage == :fixed_seed ? "fixed" : replace(string(stage),"_"=>"-")
    path=joinpath(out,"$(prefix)-report.json")
    isfile(path) || return false
    get(JSON.parsefile(path)["data"],"valid",false)
end

function report_physical_valid(out,stage)
    prefix=stage == :fixed_seed ? "fixed" : replace(string(stage),"_"=>"-")
    path=joinpath(out,"$(prefix)-report.json")
    isfile(path) || return false
    get(JSON.parsefile(path)["data"],"physical_valid",false)
end

stage_can_progress(out,stage) = stage in
    (:fixed_line_homotopy,:fixed_full_homotopy,:fixed_generator_homotopy,
        :fixed_full_generator_first) ? report_physical_valid(out,stage) :
    report_valid(out,stage)

function stage_reusable(out,stage)
    artifact_present(out,stage) || return false
    stage in (:fixed_seed,:staged,:fixed_direct_seed,:staged_direct_seed,
        :fixed_line_homotopy,:fixed_full_homotopy,:staged_homotopy,
        :fixed_generator_homotopy,:fixed_full_generator_first,
        :staged_generator_first) ?
        stage_can_progress(out,stage) : true
end

function run_worker(root,network,solver,out,stage,wall_seconds)
    log_path=joinpath(out,"$(stage)-worker.log")
    record_path=joinpath(out,"$(stage)-process.json")
    command=`$(Base.julia_cmd()) --project=$root $(joinpath(root,"examples","s2_scopf_qualification.jl")) $network $solver $out --stage $stage`
    started=now(UTC)
    process=open(log_path,"w") do log
        run(pipeline(command;stdout=log,stderr=log);wait=false)
    end
    wait_status=timedwait(() -> process_exited(process),wall_seconds;pollint=0.25)
    timed_out=wait_status == :timed_out
    if timed_out
        kill(process,Base.SIGTERM)
        timedwait(() -> process_exited(process),5.0;pollint=0.1) == :timed_out &&
            kill(process,Base.SIGKILL)
        wait(process)
    end
    finished=now(UTC)
    process_ok=!timed_out && Base.success(process)
    stage_ok=process_ok && artifact_present(out,stage)
    record=Dict("stage"=>string(stage),"started_utc"=>string(started),
        "finished_utc"=>string(finished),"wall_limit_seconds"=>wall_seconds,
        "timed_out"=>timed_out,"process_success"=>process_ok,
        "artifact_present"=>artifact_present(out,stage),"success"=>stage_ok,
        "log"=>basename(log_path))
    write_json(record_path,record)
    record
end

function orchestrate(network,solver,out,wall_seconds; lane=:declared)
    mkpath(out)
    records=Any[]
    stages=lane == :declared ? STAGES : lane == :direct_witness ? RECOVERY_STAGES :
        lane == :contingency_homotopy ? HOMOTOPY_STAGES :
        lane == :generator_first_homotopy ? GENERATOR_HOMOTOPY_STAGES :
        lane == :direct_response ? DIRECT_RESPONSE_STAGES :
        lane == :phase1_restoration ? RESTORATION_STAGES :
        error("unknown lane: $lane")
    for stage in stages
        if stage_reusable(out,stage)
            push!(records,Dict("stage"=>string(stage),"success"=>true,
                "reused"=>true,"artifact_present"=>true))
            continue
        end
        record=run_worker(dirname(@__DIR__),network,solver,out,stage,wall_seconds)
        record["reused"]=false
        push!(records,record)
        record["success"] || break
        if stage in (:fixed_seed,:staged,:fixed_direct_seed,:staged_direct_seed,
            :fixed_line_homotopy,:fixed_full_homotopy,:staged_homotopy,
            :fixed_generator_homotopy,:fixed_full_generator_first,
            :staged_generator_first) &&
            !stage_can_progress(out,stage)
            record["prerequisite_usable"]=false
            break
        end
    end
    summary=Dict("kind"=>"DroopOPF.S2ProcessRun","network"=>network,
        "solver"=>string(solver),"wall_limit_seconds_per_stage"=>wall_seconds,
        "lane"=>string(lane),"stages"=>records,
        "complete"=>all(artifact_present(out,s) for s in stages) &&
            all(report_valid(out,s) for s in filter(s->s in
                (:fixed_seed,:staged,:fixed_direct_seed,:staged_direct_seed,
                    :fixed_line_homotopy,:fixed_full_homotopy,:staged_homotopy,
                    :fixed_generator_homotopy,:fixed_full_generator_first,
                    :staged_generator_first),stages)),
        "s1_scorecard_unchanged"=>true)
    suffix=lane == :declared ? "" : "-$(replace(string(lane),"_"=>"-"))"
    write_json(joinpath(out,"orchestration$(suffix).json"),summary)
    summary
end

if abspath(PROGRAM_FILE) == @__FILE__
    network=isempty(ARGS) ? 300 : parse(Int,ARGS[1])
    solver=length(ARGS)<2 ? :ipopt : Symbol(ARGS[2])
    out=length(ARGS)<3 ? joinpath(@__DIR__,"..","artifacts","s2_scopf",
        "ieee$(network)-$(solver)") : abspath(ARGS[3])
    wall_seconds=length(ARGS)<4 ? 180.0 : parse(Float64,ARGS[4])
    lane=length(ARGS)<5 ? :declared : ARGS[5] == "--recovery" ? :direct_witness :
        ARGS[5] == "--homotopy" ? :contingency_homotopy :
        ARGS[5] == "--generator-first-homotopy" ? :generator_first_homotopy :
        ARGS[5] == "--direct-response" ? :direct_response :
        ARGS[5] == "--phase1" ? :phase1_restoration :
        error("unknown lane flag")
    println(JSON.json(orchestrate(network,solver,out,wall_seconds;lane);pretty=true))
end
