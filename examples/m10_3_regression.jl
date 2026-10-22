# Run only after explicit confirmation of the unchanged regression SCOPF fixtures.
using Test, DroopOPF, JSON, SHA
const ROOT=normpath(joinpath(@__DIR__,".."))
const OUT=abspath(ARGS[1])
length(ARGS)==2 && ARGS[2]=="confirmed-fixtures" || error("Explicit fixture confirmation is required")
get(ENV,"DROOPOPF_TEST_SUITE","")=="full" || error("Select the full retained suite")
mkpath(OUT)
const RESULT=joinpath(OUT,"regression.json")
isfile(RESULT) && error("Use a fresh regression output directory for another attempt")
paths=[joinpath(ROOT,"Project.toml"),joinpath(ROOT,"Manifest.toml"),joinpath(ROOT,"AGENTS.md"),@__FILE__]
for dir in ("src","test","examples")
    append!(paths,[joinpath(base,p) for (base,_,files) in walkdir(joinpath(ROOT,dir)) for p in files if endswith(p,".jl")])
end
protocol=Dict("suite"=>"full: canonical test/runtests.jl including extended tests and trailing joint-zero-deadband tests",
    "authorization_scope"=>"User-confirmed unchanged synthetic regression SCOPF fixtures and retries only; excludes new public-network campaigns",
    "selected_equipment"=>"tap 11 and continuous bank 201; fixed-equipment fixtures also retained",
    "absolute_bounds"=>"tap [0.95,1.05], B [0,0.06] pu; droop-security fixture tap [0.99,1.01], B [0,0.04] pu",
    "timing"=>"fixture-defined preventive/shared and corrective/per-scenario lanes",
    "movement"=>"fixture-defined absolute bounds only, or |delta tap|<=0.005 and |delta B|<=0.01 pu",
    "julia"=>string(VERSION),"julia_threads"=>Threads.nthreads(),
    "hashes"=>Dict(relpath(p,ROOT)=>bytes2hex(sha256(read(p))) for p in paths))
open(io->JSON.print(io,protocol,2),joinpath(OUT,"regression_protocol.json"),"w")
start=time_ns()
try
    suite=@testset "M10.3 full retained regression" begin
        include(joinpath(ROOT,"test","runtests.jl"))
    end
    counts=Test.get_test_counts(suite)
    result=Dict("status"=>"PASS","passes"=>counts.passes+counts.cumulative_passes,
        "failures"=>counts.fails+counts.cumulative_fails,"errors"=>counts.errors+counts.cumulative_errors,
        "broken"=>counts.broken+counts.cumulative_broken,"elapsed_seconds"=>(time_ns()-start)/1e9,
        "duration"=>counts.duration,"suite"=>"full")
    open(io->JSON.print(io,result,2),RESULT,"w")
catch err
    open(io->JSON.print(io,Dict("status"=>"FAIL","error"=>sprint(showerror,err),"elapsed_seconds"=>(time_ns()-start)/1e9),2),RESULT,"w")
    rethrow()
end
