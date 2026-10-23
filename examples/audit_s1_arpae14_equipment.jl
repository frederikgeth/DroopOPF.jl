include("s1_arpae14_equipment.jl")
function audit_equipment()
    c=read_study(joinpath(EQ_OUT,"baseline-study.json")).case
    _,_,angles,_=gated_inputs()
    rows=[JSON.parse(s) for s in readlines(joinpath(EQ_OUT,"rows.jsonl"))]
    @assert length(rows)==120 && length(unique(r["name"] for r in rows))==120
    checked=0
    for r in rows
        haskey(r,"state") || continue
        family=r["tags"]["family"]
        scaled=DroopOPF._feasibility_scaled_case(c,r["tags"]["factor"])
        original_loss=r["loss_mw"]
        eq_details(scaled,r,angles,eq_policy(scaled,family))
        abs(original_loss-r["loss_mw"])<1e-10 || error("loss replay mismatch")
        checked+=1
    end
    report=Dict("cells"=>length(rows),"states_replayed"=>checked,"mismatches"=>0,"verified"=>count(r->r["point_pass"],rows),"accepted"=>count(r->r["accepted"],rows))
    write(joinpath(EQ_OUT,"serialization_audit.json"),JSON.json(report;pretty=true))
    println(JSON.json(report))
end
audit_equipment()
