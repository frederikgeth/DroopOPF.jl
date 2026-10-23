# Bounded base-case replay of the S1 CCOpt light-load failures. No SCOPF run.
include("audit_s1_arpae500.jl")
function zero_deadband_replay()
    out=joinpath(A500_ROOT,"artifacts","s1_zero_deadband")
    mkpath(out)
    _,_,angles,costs,_=a500_inputs()
    rows=Any[]
    for factor in (.9,.95)
        name="frozen-$factor-cost-ccopt"
        old=JSON.parsefile(joinpath(A500_OUT,"attempts",name*".json"))
        seed=JSON.parsefile(joinpath(A500_OUT,"attempts","source-cost-$factor-ipopt.json"))
        c=read_study(joinpath(A500_ROOT,old["model_path"])).case
        p=a500_read_policy(old["policy"]);s=a500_state(seed["state"])
        @assert DroopOPF._feasibility_hash(s)==old["contract"]["initial"]
        @assert feasibility_fingerprint(FeasibilityProblem(c;p...,angle_limits=angles))==old["contract"]["model"]
        r=Dict{String,Any}("name"=>name,"source_attempt"=>relpath(joinpath(A500_OUT,"attempts",name*".json"),A500_ROOT),
            "original_status"=>old["solver_status"],"original_accepted"=>old["accepted"],
            "contract"=>old["contract"],"policy"=>old["policy"],"model_path"=>old["model_path"],
            "formulation"=>"constant zero deadband; affine raw Q; two projection pairs per controller")
        opts=Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),
            "tol"=>1e-11,"acceptable_tol"=>1e-11,"bound_relax_factor"=>0.,
            "max_iter"=>old["contract"]["iterations"],"max_wall_time"=>old["contract"]["seconds"])
        println("START ",name);flush(stdout)
        result=optimize_joint_design(c;p...,initial_state=s,encoding=:complementarity,
            optimizer_attributes=opts,_measurement_hook=(phase,m)->begin
                if phase==:built
                    idx=DroopOPF._bus_indices(c.network)
                    for b in c.network.branches
                        b.available || continue
                        lo,hi=angles[b.id]
                        f=variable_by_name(m,"va[$(idx[b.from_bus])]");t=variable_by_name(m,"va[$(idx[b.to_bus])]")
                        @constraint(m,lo<=f-t<=hi)
                    end
                    pg=[variable_by_name(m,"pg[$i]") for i in eachindex(c.generators)]
                    @objective(m,Min,sum(pg)-sum(l.p for l in c.loads))
                    r["variables"]=num_variables(m)
                elseif phase==:solved
                    r["ccopt_diagnostics"]=ccopt_diagnostics(m)
                    r["ccopt_encoding_audit"]=ccopt_encoding_audit(m)
                end
            end)
        r["solver_status"]=string(result.opf.termination_status)
        r["solver_success"]=result.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
        r["accepted"]=false;r["point_pass"]=false
        if !isnothing(result.opf.state)
            r["state"]=a500_json(result.opf.state);r["taps"]=a500_json(result.taps);r["susceptances"]=a500_json(result.susceptances)
            a500_details(c,r,angles,p,costs)
        end
        a500_save(joinpath(out,name*".json"),r);push!(rows,r)
        println("END ",name," status=",r["solver_status"]," accepted=",r["accepted"]);flush(stdout)
    end
    a500_save(joinpath(out,"summary.json"),Dict("attempts"=>rows,
        "code_hashes"=>Dict(f=>bytes2hex(sha256(read(joinpath(A500_ROOT,f)))) for f in
            ("src/complementarity.jl","src/jump.jl","examples/s1_zero_deadband_replay.jl")),
        "scope"=>"Two original cost-OPF starts; original budgets, fixed equipment, loss objective, physical constraints and tolerances; serial execution"))
end
abspath(PROGRAM_FILE)==(@__FILE__) && zero_deadband_replay()
