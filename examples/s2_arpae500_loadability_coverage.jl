include("s2_arpae500_loadability.jl")

function el_cover_confirmed()
    controller=read_study(joinpath(EL_OUT,"decomposition/shared-controller.json"))
    raw=JSON.parsefile(joinpath(EL_OUT,"decomposition/shared-states.json"));states=Dict()
    for r in raw
        states[(Float64(r["factor"]),Symbol(r["id"]))]=(;state=a500_state(r["state"]),
            taps=a500_settings(r["taps"]),banks=a500_settings(r["banks"]),dr=a500_settings(r["dr"]),shed=a500_settings(r["shed"]))
    end
    el_emergency_scan((;study=controller,states),(1.1,1.05,1.,.95,.9);label="compact-five-demand")
end

abspath(PROGRAM_FILE)==(@__FILE__) && el_cover_confirmed()
