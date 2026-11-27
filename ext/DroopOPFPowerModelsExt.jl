module DroopOPFPowerModelsExt
using JuMP, Ipopt, JSON
import PowerModels as P
import DroopOPF
using DroopOPF: NetworkDesignContract
const STUDY_ITERATION_LIMIT=1000
const KERNEL_FILES=sort!([@__FILE__;[joinpath(@__DIR__,"network_design",n) for n in readdir(joinpath(@__DIR__,"network_design")) if endswith(n,".jl")];joinpath(@__DIR__,"../src/network_design_contract.jl")])
const KERNEL_DIGEST=bytes2hex(DroopOPF.SHA.sha256(join(basename(p)*" "*bytes2hex(DroopOPF.SHA.sha256(read(p)))*"\n" for p in KERNEL_FILES)))
backend_signature()=Dict("DroopOPF"=>string(pkgversion(DroopOPF)),"PowerModels"=>string(pkgversion(P)),
    "JuMP"=>string(pkgversion(JuMP)),"Ipopt"=>string(pkgversion(Ipopt)),"Julia"=>string(VERSION))
include("network_design/helpers.jl")
include("network_design/allocation.jl")
include("network_design/equipment.jl")
include("network_design/physics.jl")
include("network_design/solver.jl")
include("network_design/starts.jl")
include("network_design/workflow.jl")
include("network_design/series.jl")
end
