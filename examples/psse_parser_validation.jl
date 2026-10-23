# Parser/import validation only: no optimization, no PSS/E installation.
# julia --project=. examples/psse_parser_validation.jl /fresh/output /public/500.raw
using DroopOPF, JSON, SHA
const PSSE_ROOT=normpath(joinpath(@__DIR__,".."))
psse_json(path,value)=write(path,JSON.json(DroopOPF._json_data(value);pretty=true)*"\n")
function psse_validate_campaign(out,large)
    ispath(out)&&error("Fresh output directory required")
    mkpath(out);mkpath(joinpath(out,"inputs"))
    cp(large,joinpath(out,"inputs","public_v33_southcarolina500.raw"))
    sources=[joinpath(PSSE_ROOT,"test/data/psse/synthetic_v$v.raw") for v in (33,34,36)]
    push!(sources,joinpath(PSSE_ROOT,"test/data/psse/public_v34_ieee14.raw"))
    append!(sources,[joinpath(PSSE_ROOT,"test/data/arpae/c1_network01",s,"case.raw") for s in
        ("scenario_01","scenario_01_pmin0","scenario_01_pmin0_qsym","scenario_02","scenario_02_pmin0","scenario_02_pmin0_qsym")])
    push!(sources,joinpath(out,"inputs","public_v33_southcarolina500.raw"))
    psse_json(joinpath(out,"public-500-provenance.json"),(;
        url="https://raw.githubusercontent.com/powsybl/powsybl-core/c0a2243e3d6dd79e50eaac072df63f72df33752a/psse/psse-model-test/src/main/resources/illinois/synthetic/SouthCarolina500.RAW",
        upstream_revision="c0a2243e3d6dd79e50eaac072df63f72df33752a",
        sha256=bytes2hex(sha256(read(large))),description="Public synthetic Illinois/Texas A&M South Carolina 500-bus test network via PowSyBl; original bytes retained"))
    rows=Any[]
    for (index,path) in enumerate(sources)
        d=parse_psse_raw(path);imported=import_psse_case(d;unrated_limit=1e6)
        c=imported.case;b=power_balance(c,imported.initial_state)
        a=validate_equilibrium(c,imported.initial_state)
        row=(;source=relpath(path,PSSE_ROOT),sha256=bytes2hex(sha256(read(path))),revision=d.revision,
            schema_fixture=occursin("synthetic_v",basename(path)),
            parsed_counts=Dict(k=>length(v) for (k,v) in d.sections),
            buses=length(c.network.buses),generators=length(c.generators),loads=length(c.loads),
            branches=length(c.network.branches),shunts=length(c.network.shunts),
            imported=true,supplied_point_valid=a.valid,supplied_balance_max_pu=a.power_balance_max,
            supplied_point_report=a,diagnostics=imported.diagnostics)
        push!(rows,row)
        dir=joinpath(out,"cases",string(index));mkpath(dir)
        write_study(joinpath(dir,"study.json"),Study(c))
        psse_json(joinpath(dir,"supplied-state.json"),imported.initial_state)
        psse_json(joinpath(dir,"source-identities.json"),imported.source_ids)
        psse_json(joinpath(dir,"summary.json"),row)
    end
    psse_json(joinpath(out,"summary.json"),(;parsed_and_imported=length(rows),
        native_v36_export_tested=false,optimization_runs=0,rows))
    println("Parsed/imported ",length(rows)," files; no optimization performed")
end
length(ARGS)==2 || error("Supply fresh output directory and public 500-bus RAW path")
psse_validate_campaign(abspath(ARGS[1]),abspath(ARGS[2]))
