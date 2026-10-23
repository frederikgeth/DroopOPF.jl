# Standalone local validation against the state saved in a PSS/E RAW file.
# julia --project=. examples/check_psse_file.jl network.raw [report.json]
using DroopOPF
function main(args)
    length(args) in (1,2) || error("Usage: check_psse_file.jl network.raw [report.json]")
    source=abspath(args[1])
    destination=length(args)==2 ? abspath(args[2]) : joinpath(pwd(),splitext(basename(source))[1]*".validation.json")
    report=check_psse_file(source;report_path=destination)
    println("Validation report: ",destination)
    println("Saved power-flow balance consistent: ",get(report,"power_flow_consistent",nothing))
    println("Overall supported checks passed: ",report["valid"])
    report["valid"] ? 0 : 2
end
if abspath(PROGRAM_FILE)==@__FILE__
    exit(main(ARGS))
end
