include("s1_experiments.jl")
include("scaling_case.jl")

function s1_robustness(out)
    mkpath(out);rows=[]
    for n in (4,32)
        case=scaling_case(n;heterogeneous=true);p=scaling_policies(n)
        start=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_exact_hessian","start-$n.json")).opf.state
        write_study(joinpath(out,"study-$n.json"),Study(case))
        for solver in (:ipopt,:madnlp), mode in (:feasible,:flat_low,:flat_high)
            policies=mode==:feasible ? p : s1_reseed(case,p;fraction=mode==:flat_low ? .2 : .8)
            state=mode==:feasible ? start : s1_flat(case)
            row,_=s1_attempt(out,"n$n-$solver-$mode",case,state;policies,solver,
                tags=Dict("study"=>"starts","start"=>string(mode)))
            push!(rows,row);s1_summary(out,rows)
        end
        n==32 || continue
        for family in (:droop_controls,:tap_controls,:shunt_controls)
            total=length(getfield(p,family))
            for count in unique([0,1,total÷4,total÷2,total])
                policies=merge(p,NamedTuple{(family,)}((getfield(p,family)[1:count],)))
                row,_=s1_attempt(out,"count-$family-$count",case,start;policies,
                    tags=Dict("study"=>"count","family"=>string(family),"count"=>count))
                push!(rows,row);s1_summary(out,rows)
            end
        end
        for epsilon in (1e-4,1e-5,1e-7)
            row,_=s1_attempt(out,"smoothing-$epsilon",case,start;policies=p,epsilon,
                tags=Dict("study"=>"smoothing"))
            push!(rows,row);s1_summary(out,rows)
        end
        state=start;policies=p
        for epsilon in (1e-4,1e-5,1e-6)
            row,r=s1_attempt(out,"continuation-$epsilon",case,state;policies,epsilon,
                tags=Dict("study"=>"continuation"))
            push!(rows,row);s1_summary(out,rows)
            # Continuation can use a smoothed-feasible iterate that fails exact replay.
            isnothing(r) || isnothing(r.opf.state) || !get(row,"solver_valid",false) || !get(row,"policy_valid",false) || begin
                state=r.opf.state;policies=s1_reseed(case,p;result=r)
            end
        end
        onlydroop=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=p.droop_controls)
        row,r=s1_attempt(out,"staged-droop",case,start;policies=onlydroop,tags=Dict("study"=>"staged"))
        push!(rows,row)
        if row["valid"]
            row,_=s1_attempt(out,"staged-joint",case,r.opf.state;policies=s1_reseed(case,p;result=r),tags=Dict("study"=>"staged"))
            push!(rows,row)
        end
        s1_summary(out,rows)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_robustness(abspath(ARGS[1]))
