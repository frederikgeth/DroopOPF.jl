# Independent normal-limit designs; no shared controller across demands.
include("s2_500bus_solver_demand_qualification.jl")
function sdq_independent_demands()
    isempty(strip(get(ENV,"SDQ_CONTROL_CONFIRMATION",""))) && error("Campaign confirmation required")
    for f in (.9,.95,1.05)
        for solver in (:ipopt,:madnlp,:ccopt)
            recovery=solver==:ccopt
            label="$(solver)-$(round(Int,f*10000))"*(recovery ? "-recovery" : "")
            isfile(joinpath(SDQ_OUT,"summary-$label.json")) && continue
            sdq_run(solver;factor=f,max_rounds=2,separator_solver=:ipopt,recovery)
            GC.gc()
        end
    end
    # The independently verified necessary active-loss relaxation excludes
    # 110%/G60 even before droop/controller and preventive-response constraints.
    # Do not spend local solves trying to overturn this original-policy proof.
    proof=JSON.parsefile(joinpath(S2500_OUT,"active_loss_diagnostic/independent_audit.json"))
    @assert proof["verified"] && proof["certified_infeasible"] && proof["acceptance_tolerance_robust"]
    fd_save(joinpath(SDQ_OUT,"normal-110-certificate.json"),(;factor=1.1,classification="certified_infeasible_under_original_normal_full_demand_policy",
        applies_to_solvers=["ipopt","madnlp","ccopt"],native_optimizer_calls=0,critical_outage="generator_60",
        proof="../active_loss_diagnostic/result.json",verification="../active_loss_diagnostic/independent_audit.json",
        proof_sha256=bytes2hex(sha256(read(joinpath(S2500_OUT,"active_loss_diagnostic/result.json")))),
        verification_sha256=bytes2hex(sha256(read(joinpath(S2500_OUT,"active_loss_diagnostic/independent_audit.json")))),
        emergency_policy_excluded_from_certificate=true,multi_demand_normal_target_accepted=false))
end
abspath(PROGRAM_FILE)==(@__FILE__) && sdq_independent_demands()
