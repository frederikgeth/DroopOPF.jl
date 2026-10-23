# Serial warmed, fixed-equipment base-case OPF profile. No SCOPF.
using DroopOPF, JSON, SHA, LinearAlgebra, JuMP, Ipopt
const ROOT=normpath(joinpath(@__DIR__,".."))
const OUT=abspath(ARGS[1])
BLAS.set_num_threads(1)
function save(path,x)
    open(io->JSON.print(io,DroopOPF._json_data(x),2),path,"w")
end
function run_profile()
    mkpath(OUT)
    isfile(joinpath(OUT,"protocol.json")) && error("Use a fresh profile directory")
    sources=[joinpath(ROOT,"artifacts/m7_3/input-study.json"),joinpath(ROOT,"artifacts/m7_3/evidence.json")]
    append!(sources,[joinpath(ROOT,"artifacts/m7_3/design-$(t)$(s)$(d)-$run.json") for t in 0:1 for s in 0:1 for d in 0:1 for run in 1:2])
    append!(sources,[@__FILE__,joinpath(ROOT,"Project.toml"),joinpath(ROOT,"Manifest.toml")])
    append!(sources,[joinpath(ROOT,"src",p) for p in readdir(joinpath(ROOT,"src")) if endswith(p,".jl")])
    opts=Dict{String,Any}("tol"=>1e-9,"acceptable_tol"=>1e-9,"bound_relax_factor"=>0.,"max_iter"=>500,"max_cpu_time"=>20.)
    save(joinpath(OUT,"protocol.json"),Dict("scope"=>"three-bus nominal fixed-equipment known-witness base-case OPF",
        "warmups_per_tag"=>1,"measured_repetitions_per_tag"=>3,"tags"=>[string(t,s,d) for t in 0:1 for s in 0:1 for d in 0:1],
        "policy"=>"all equipment and curves frozen to best saved nominal design per tag; same dispatch-deviation objective; no design variables",
        "solver"=>"Ipopt","solver_options"=>opts,"smooth_epsilon"=>1e-5,
        "phase_scope"=>"build includes validation/setup; solve ends at optimize! return; extraction ends at result construction; physical validation timed separately; JSON/disk I/O excluded",
        "memory_scope"=>"Julia allocated bytes for optimizer construction/solve/extraction only; excludes native allocation and independent validation",
        "comparison_scope"=>"one solver and small fixed models; not a solver ranking, large-system forecast, or performance regression threshold",
        "hashes"=>Dict(relpath(p,ROOT)=>bytes2hex(sha256(read(p))) for p in sources),
        "environment"=>Dict("julia"=>string(VERSION),"julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
            "cpu"=>Sys.CPU_NAME,"architecture"=>string(Sys.ARCH),"kernel"=>string(Sys.KERNEL),"ipopt_jl"=>string(Base.pkgversion(Ipopt)))))
    case=read_study(joinpath(ROOT,"artifacts/m7_3/input-study.json")).case
    records=[]
    for t in 0:1,s in 0:1,d in 0:1
        tag=string(t,s,d)
        candidates=[read_joint_design(joinpath(ROOT,"artifacts/m7_3/design-$tag-$run.json")) for run in 1:2]
        @assert all(validate_joint_design(case,x).valid for x in candidates)
        chosen=candidates[argmin([x.opf.objective for x in candidates])]
        fixed=with_joint_settings(case,chosen)
        write_study(joinpath(OUT,"case-$tag.json"),Study(fixed))
        for repetition in 0:3
            stamps=Dict{Symbol,UInt64}();model=Ref{Any}()
            start=time_ns()
            measured=@timed optimize_joint_design(fixed;initial_state=chosen.opf.state,smooth_epsilon=1e-5,
                optimizer_attributes=opts,_measurement_hook=(phase,m)->begin stamps[phase]=time_ns();model[]=m;end)
            result=measured.value
            validation_start=time_ns();v=validate_joint_design(fixed,result);validation_end=time_ns()
            r=Dict("tag"=>tag,"repetition"=>repetition,"warmup"=>repetition==0,"accepted"=>v.valid,
                "build_seconds"=>(stamps[:built]-start)/1e9,"solve_seconds"=>(stamps[:solved]-stamps[:built])/1e9,
                "extraction_seconds"=>(stamps[:extracted]-stamps[:solved])/1e9,
                "validation_seconds"=>(validation_end-validation_start)/1e9,
                "optimizer_wall_seconds"=>measured.time,"julia_allocated_bytes"=>measured.bytes,"gc_seconds"=>measured.gctime,
                "variables"=>num_variables(model[]),"constraints_including_variable_bounds"=>num_constraints(model[];count_variable_in_set_constraints=true),
                "result"=>DroopOPF._json_data(result.opf),"validation"=>DroopOPF._json_data(v),"case_file"=>"case-$tag.json")
            push!(records,r);save(joinpath(OUT,"$tag-$repetition.json"),r)
            println(tag," repetition ",repetition," accepted=",v.valid);flush(stdout)
        end
    end
    save(joinpath(OUT,"attempts.json"),records)
    @assert length(records)==32 && all(x["accepted"] for x in records)
end
run_profile()
