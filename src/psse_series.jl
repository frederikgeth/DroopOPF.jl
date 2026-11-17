"""Local-only RAW operating points. `imports` retains confidential source text,
identities and saved states; never serialize this object into a shareable report.
`study` has period loads and generator start hints, not fixed generation schedules.
"""
struct PSSETimeSeries
    study::MultiPeriodStudy
    imports::Vector{PSSEImport}
    saved_reports::Vector{Any}
    changes::Vector{NamedTuple}
    initial_states::Vector{ACState{Float64}}
    build_reports::Vector{Dict{String,Any}}
    generator_technologies::Vector{Dict{Int,Dict{String,Any}}}
    ibr_fits::Vector{Dict{String,Any}}
    reactive_assignments::Vector{Vector{ReactiveControlAssignment}}
end

"""Load one folder of RAW snapshots in explicit `files` order, or lexical basename
order. Supply durations in that same order (no timestamps inferred from names).
Loads, saved voltages/angles, generator P/Q hints and generator on/off status may vary.
Identity order, topology, branch availability, ratings, capabilities, taps and shunts
must agree exactly. Generator commitment is supplied, not optimized.
No ramps or equipment movement capabilities are inferred from RAW.
Saved-state reports and errors are confidential. This function performs no writes
or network calls. Set `require_valid=true` to gate on saved-solution replay.
`zone=4` extracts RAW BUS ZONE 4 with fixed saved-terminal boundary P/Q and
largest-Pmax physical generator angle reference. `initial_states` follows the
built model; `imports` and `saved_reports` retain the confidential full network.
`build_reports` retains per-period reference, scope and boundary assumptions.
Optional `generator_csv` classifies generators and produces confidential exploratory
IBR Q(V) fits (`ibr_fits`); `ibr_fit_options` configures diagnostic fitting thresholds.
Synchronous generators/condensers receive explicit AVR assignments from RAW VS/IREG
under the user-requested technology policy; inferred IBR curves are not installed.
"""
function load_psse_series(folder::AbstractString; files=nothing, duration_hours=nothing,
    ramp_limits=Dict(), angle_limits=Dict(), encoding=:utf8, require_valid=false,
    validation_options=(;), unrated_limit=nothing,zone::Union{Nothing,Integer}=nothing,
    generator_csv=nothing,ibr_fit_options=(;))
    paths=_psse_series_paths(folder,files)
    imports=PSSEImport[];reports=Any[]
    for p in paths
        r=import_psse_case(parse_psse_raw(p;encoding);id="local_period",unrated_limit)
        if isnothing(zone) && !isempty(imports)
            isequal(r.source_ids,imports[1].source_ids) || throw(ArgumentError(
                "period source identities/order changed; reconcile locally before importing"))
        end
        report=validate_psse_saved_solution(r;validation_options...)
        require_valid && !report["valid"] && throw(ArgumentError("saved period replay failed"))
        push!(imports,r);push!(reports,report)
    end
    durations=isnothing(duration_hours) ? ones(length(imports)) : duration_hours
    built=isnothing(zone) ? [(;case=r.case,initial_state=r.initial_state,
        report=Dict{String,Any}("scope"=>"full imported network; supplied reference"),source_ids=r.source_ids) for r in imports] :
        [extract_psse_zone(r;zone) for r in imports]
    all(isequal(b.source_ids,built[1].source_ids) for b in built) || throw(ArgumentError("period zone source identities changed"))
    study=MultiPeriodStudy([b.case for b in built];duration_hours=durations,ramp_limits,angle_limits)
    technologies=Dict{Int,Dict{String,Any}}[];fits=Dict{String,Any}[]
    assignments=[ReactiveControlAssignment[] for _ in built]
    if !isnothing(generator_csv)
        metadata=read_psse_generator_csv(generator_csv)
        fullmapping,unmatched=_psse_technology_map(imports,metadata)
        technologies=[Dict(g.id=>fullmapping[t][g.id] for g in b.case.generators) for (t,b) in enumerate(built)]
        fits=_psse_ibr_fits(imports,built,fullmapping;ibr_fit_options...)
        assignments,avr_policies=_psse_avr_assignments(imports,built,fullmapping)
        for (t,b) in enumerate(built)
            b.report["generator_technologies"]=_json_data(technologies[t])
            b.report["unmatched_csv_rows"]=[Dict(string(k)=>getfield(m,k) for k in keys(m)) for m in unmatched]
            b.report["ibr_fit_summary"]=[Dict("generator_id"=>f["generator_id"],"status"=>f["status"]) for f in fits]
            t==1 && (b.report["ibr_fit_details"]=fits)
            b.report["avr_policy"]=avr_policies[t]
            b.report["technology_control_policy"]="synchronous generator/condenser AVR as requested; IBR fits remain exploratory; source capabilities unchanged"
        end
    elseif !isempty(ibr_fit_options)
        throw(ArgumentError("IBR fitting options require generator_csv"))
    end
    PSSETimeSeries(study,imports,reports,_psse_series_changes([r.raw for r in imports]),
        [b.initial_state for b in built],[b.report for b in built],technologies,fits,assignments)
end

"""Allowlisted diagnostic with no paths, names, identifiers, hashes, counts,
operating values, exception text or source metadata. Manual organizational review
is still required before sharing even these aggregate status flags.
"""
psse_series_diagnostic(series::PSSETimeSeries)=Dict(
    "schema"=>"droopopf-raw-series-status-v1",
    "import_status"=>all(get(get(r,"avr_policy",Dict("qualified"=>true)),"qualified",false) for r in series.build_reports) ? "compatible" : "control_policy_unqualified",
    "saved_replay"=>all(r["valid"] for r in series.saved_reports) ? "passed" : "not_qualified",
    "security_status"=>"not_run")

"""Confidential, persistent-in-memory comparison of RAW snapshots, including
snapshots that cannot form a fixed-equipment MultiPeriodStudy. No solver is run.
Changes compare consecutive periods. `raws` preserves all source material.
"""
struct PSSESeriesInspection
    raws::Vector{PSSERawData}
    changes::Vector{NamedTuple}
end

function _psse_inspection_records(raw,section)
    records=get(raw.sections,section,PSSERecord[])
    keyspec= section==:bus ? [:I] : section in (:load,:generator,:fixed_shunt,:switched_shunt) ?
        [:I,:ID] : section==:branch ? [:I,:J,:CKT] : section==:transformer ? [:I,:J,:K,:CKT] : Symbol[]
    result=Dict{String,Dict{Symbol,Any}}();order=String[]
    for (i,r) in enumerate(records)
        identity=isempty(keyspec) ? "record $i" : repr(Tuple(get(r.fields,k,nothing) for k in keyspec))
        haskey(result,identity) && throw(ArgumentError("duplicate source identity during local inspection"))
        fields=copy(r.fields)
        isempty(keyspec) && (fields[:opaque_rows]=r.rows)
        result[identity]=fields;push!(order,identity)
    end
    result,order
end

function _psse_series_changes(raws)
    changes=NamedTuple[]
    operating=Dict(:bus=>Set([:VM,:VA]), :generator=>Set([:PG,:QG]),
        :load=>Set([:PL,:QL,:IP,:IQ,:YP,:YQ,:DGENP,:DGENQ]))
    function add(t,section,identity,field,before,after;category=:major)
        push!(changes,(;from_period=t-1,to_period=t,section,identity,field,before,after,category))
    end
    for t in 2:length(raws)
        a,b=raws[t-1],raws[t]
        for (field,x,y) in ((:header,a.header,b.header),(:titles,a.titles,b.titles))
            isequal(x,y) || add(t,:case,"case",field,x,y;category=:metadata)
        end
        for section in sort!(collect(union(keys(a.sections),keys(b.sections)));by=string)
            left,lo=_psse_inspection_records(a,section);right,ro=_psse_inspection_records(b,section)
            if Set(lo)==Set(ro) && lo!=ro
                add(t,section,"section",:record_order,lo,ro)
            end
            for id in sort!(collect(union(keys(left),keys(right))))
                if !haskey(left,id) || !haskey(right,id)
                    add(t,section,id,:record,get(left,id,nothing),get(right,id,nothing))
                    continue
                end
                x,y=left[id],right[id]
                for field in sort!(collect(union(keys(x),keys(y)));by=string)
                    before=get(x,field,nothing);after=get(y,field,nothing)
                    isequal(before,after) && continue
                    category=field in get(operating,section,Set{Symbol}()) ? :operating_point : :major
                    add(t,section,id,field,before,after;category)
                end
            end
        end
    end
    changes
end

"""Inspect RAW day snapshots without requiring unchanged topology or commitment.
On/off, additions/removals, limits, taps, shunts, control metadata and opaque data
changes remain inspectable. Operating-point changes are recorded separately.
Comparisons are exact parsed-field comparisons, not engineering significance
thresholds; comments/formatting are retained in raws but are not change events.
All output and exception details are confidential and must remain on the work machine.
"""
function inspect_psse_series(folder::AbstractString;files=nothing,encoding=:utf8)
    paths=_psse_series_paths(folder,files)
    raws=[parse_psse_raw(p;encoding) for p in paths]
    PSSESeriesInspection(raws,_psse_series_changes(raws))
end

"""Inspect an already imported series at any time, without rereading files."""
inspect_psse_series(series::PSSETimeSeries)=begin
    raws=[r.raw for r in series.imports]
    PSSESeriesInspection(raws,_psse_series_changes(raws))
end

_psse_html(x)=replace(string(x),'&'=>"&amp;",'<'=>"&lt;",'>'=>"&gt;",'"'=>"&quot;",'\''=>"&#39;")

"""Write a confidential offline change browser to an IO opened by the caller.
No remote assets or network requests. Keep the generated HTML outside Git and
cloud sync; it contains private source identities and values, not shareable diagnostics.
"""
function write_psse_series_inspection(io::IO,inspection::PSSESeriesInspection)
    print(io,"""<!doctype html><html lang="en"><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>Local RAW changes — confidential</title>
<style>body{font:16px system-ui;margin:24px}table{border-collapse:collapse;width:100%}td,th{padding:8px;border-bottom:1px solid #888;text-align:left;overflow-wrap:anywhere}input{padding:8px} .scroll{overflow:auto}</style>
<h1>RAW period changes — confidential</h1>
<p>Consecutive-period comparisons. Major changes include commitment, equipment, topology and limits. No security qualification.</p>
<label>Filter <input id="search" type="search"></label>
<label><input id="operating" type="checkbox"> Include load, dispatch and saved voltage changes</label>
<p id="count" aria-live="polite"></p><div class="scroll"><table><thead><tr>
<th>Periods</th><th>Category</th><th>Section</th><th>Identity</th><th>Field</th><th>Before</th><th>After</th>
</tr></thead><tbody>""")
    for c in inspection.changes
        print(io,"<tr data-category=\"",c.category,"\">")
        for value in ("$(c.from_period) → $(c.to_period)",c.category,c.section,c.identity,c.field,c.before,c.after)
            print(io,"<td>",_psse_html(value),"</td>")
        end
        print(io,"</tr>")
    end
    print(io,"""</tbody></table></div><script>
const rows=[...document.querySelectorAll('tbody tr')], search=document.getElementById('search'), operating=document.getElementById('operating');
function update(){let n=0;for(const row of rows){row.hidden=(!operating.checked&&row.dataset.category==='operating_point')||!row.textContent.toLowerCase().includes(search.value.toLowerCase());if(!row.hidden)n++;}document.getElementById('count').textContent=n+' of '+rows.length+' changes shown';}
search.addEventListener('input',update);operating.addEventListener('change',update);update();
</script></html>""")
    nothing
end

function _psse_series_paths(folder,files)
    root=realpath(folder)
    names=isnothing(files) ? sort(filter(n->endswith(lowercase(n),".raw"),readdir(root))) : collect(files)
    isempty(names) && throw(ArgumentError("no RAW periods supplied"))
    all(n->n isa AbstractString && basename(n)==n && endswith(lowercase(n),".raw"),names) ||
        throw(ArgumentError("files must be RAW basenames within the input folder"))
    length(unique(names))==length(names) || throw(ArgumentError("duplicate periods"))
    paths=[joinpath(root,n) for n in names]
    all(p->isfile(p) && !islink(p) && dirname(realpath(p))==root,paths) ||
        throw(ArgumentError("periods must be regular local files, without symlinks"))
    paths
end
