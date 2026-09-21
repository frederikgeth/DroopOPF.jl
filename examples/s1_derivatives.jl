include("s1_diagnostics.jl")
include("scaling_case.jl")
out=abspath(ARGS[1])
case=scaling_case(4;heterogeneous=true)
start=read_joint_design("artifacts/s1_convergence/start-4.json").opf.state
for enabled in (false,true)
    p=enabled ? scaling_policies(4) : NamedTuple()
    s1_solve(out,enabled ? "joint-derivatives" : "fixed-derivatives",case,start;policies=p,silent=false,
        options=Dict("max_iter"=>0,"derivative_test"=>"second-order","derivative_test_tol"=>1e-4,
            "derivative_test_perturbation"=>1e-7,"print_level"=>5))
end
