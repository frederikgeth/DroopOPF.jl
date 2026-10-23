include("s1_arpae14_gated.jl")
function audit_gated(out=GATED_OUT)
    gated_assert_inputs(out)
    source,anchor,angles,candidates=gated_inputs()
    rows=JSON.parsefile(joinpath(out,"primary_matrix_summary.json"));checked=0;accepted=0
    for row in rows
        tags=row["tags"];nominal=tags["variant"]=="source" ? source : candidates[tags["variant"]]
        c=DroopOPF._feasibility_scaled_case(nominal,tags["factor"])
        result=read_joint_design(joinpath(out,row["name"]*"-design.json"))
        frozen=DroopOPF._joint_droop_case(c,result)
        p=FeasibilityProblem(frozen;tap_controls=result.tap_controls,shunt_controls=result.shunt_controls,angle_limits=angles)
        gate=read_feasibility_result(joinpath(out,row["name"]*"-gate.json"),p)
        design_check=validate_joint_design(c,result)
        calibration=check_feasibility(FeasibilityProblem(DroopOPF._joint_droop_case(nominal,result);
            tap_controls=result.tap_controls,shunt_controls=result.shunt_controls,angle_limits=angles);
            witnesses=[FeasibilityWitness(anchor)],solve_missing=false)
        (calibration.status==:feasible)==row["calibration_pass"] || error("calibration replay changed")
        valid=gate.status==:feasible && design_check.policy_valid &&
            (!get(tags,"calibration_coupled",false) || calibration.status==:feasible)
        valid==get(row,"point_pass",false) || error("acceptance replay changed: $(row["name"])")
        if get(row,"replacement_qualified",false)
            row["calibration_pass"] || error("uncalibrated replacement accepted")
            family=tags["family"]
            path=family in ("fixed","tap","shunt","tap_shunt") ?
                joinpath(out,"$(tags["variant"])-$family-final-qualification.json") :
                joinpath(out,row["name"]*"-qualification.json")
            JSON.parsefile(path)["data"]["accepted"] || error("replacement lacks complete qualification")
        end
        checked+=1;accepted+=valid
    end
    payload=Dict("attempts_replayed"=>checked,"verified_points"=>accepted,"source_input_hashes_unchanged"=>true,
        "qualification_claims_checked"=>count(r->get(r,"replacement_qualified",false),rows))
    write(joinpath(out,"independent_audit.json"),JSON.json(payload;pretty=true))
    println(payload)
end
if abspath(PROGRAM_FILE)==@__FILE__
    audit_gated()
end
