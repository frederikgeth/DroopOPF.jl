# Local preflight only: no solve, telemetry, reports or serialized network written.
using DroopOPF, JSON
function main(args)
    length(args) in (1,2,3) || (println(stderr,"Usage: julia --project examples/check_psse_series.jl EXTERNAL_FOLDER [ZONE [GENERATOR_CSV]]");return 2)
    try
        folder=realpath(args[1])
        zone=length(args)>=2 ? parse(Int,args[2]) : nothing
        generator_csv=length(args)==3 ? realpath(args[3]) : nothing
        for input in (folder,isnothing(generator_csv) ? folder : dirname(generator_csv))
            parent=input
            while true
                ispath(joinpath(parent,".git")) && error("input inside Git checkout")
                next=dirname(parent);next==parent && break;parent=next
            end
        end
        series=load_psse_series(folder;zone,generator_csv)
        println(JSON.json(psse_series_diagnostic(series)))
        return 0
    catch
        # Never print exception text, backtrace, filenames or RAW records.
        println(stderr,"Local RAW series preflight failed. Inspect confidential data locally; do not share parser errors.")
        return 1
    end
end
exit(main(ARGS))
