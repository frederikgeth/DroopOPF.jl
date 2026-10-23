# Bounded retuning within unchanged S2 curve bounds; this alone is not multi-demand qualification.
function md_free_extension(folder;factor=1.065)
    ispath(folder)&&error("Choose a fresh extension directory")
    x=md_seed()
    source=joinpath(P2MD,"s2-allowance/stage-1/500/progressive/round-1/master/primary")
    seed=P2S2.el_read_point(source;stage="solve")
    ids=Set([:branch_36,:branch_219,:branch_562,:generator_14,:generator_60])
    events=[e for e in x.events if e.id in ids]
    P2S2.fd_save(joinpath(folder,"protocol.json"),(;factor,source,free_controller=true,zero_shedding=false,
        master_seconds=90.,retry_seconds=180.,physical_bounds_changed=false,
        meaning="single-demand candidate search; any candidate needs fresh exhaustive and cross-demand qualification"))
    a=P2S2.md_polish_attempt(x,joinpath(folder,"primary"),(factor,),events;seed,zero_shedding=false,seconds=90.)
    selected=a
    if !a.summary.accepted
        warm=!isnothing(a.audit)&&a.audit["physical_valid"] ? a.point : seed
        selected=P2S2.md_polish_attempt(x,joinpath(folder,"retry"),(factor,),events;seed=warm,zero_shedding=false,seconds=180.,retry=true)
    end
    candidates=[a,selected]
    index=findlast(c->!isnothing(c.audit)&&c.audit["physical_valid"],candidates)
    candidate=isnothing(index) ? nothing : candidates[index]
    result=(;factor,native_master_accepted=selected.summary.accepted,
        physical_candidate_available=!isnothing(candidate),
        candidate_folder=isnothing(candidate) ? nothing : candidate.summary.folder,
        exhaustive_accepted=false,physical_infeasibility_proven=false)
    P2S2.fd_save(joinpath(folder,"summary.json"),result);result
end
