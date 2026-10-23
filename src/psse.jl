"""One PSS/E RAW record, with typed known fields, original token rows and source lines.
Opaque sections retain token rows without assigning electrical semantics.
"""
struct PSSERecord
    fields::Dict{Symbol,Any}
    rows::Vector{Vector{String}}
    lines::Vector{Int}
end
"""Parsed full-case RAW revision 33, 34 or 36; source text and unknown sections are retained.
This is bus/branch RAW, not binary SAV, DYR, SEQ or RAWX. Parsing does not certify
that every equipment model can be represented by the DroopOPF AC domain.
"""
struct PSSERawData
    revision::Int
    base_power::Float64
    base_frequency::Float64
    titles::Tuple{String,String}
    header::Dict{Symbol,Any}
    sections::Dict{Symbol,Vector{PSSERecord}}
    diagnostics::Vector{String}
    source::String
    text::String
end
"""Strict AC import plus unmodified supplied operating-point data and source-ID maps."""
struct PSSEImport
    case::Case
    initial_state::ACState{Float64}
    source_ids::Dict{Symbol,Dict{Int,Any}}
    diagnostics::Vector{String}
    raw::PSSERawData
end

# Interface field layouts independently implemented from the versioned RAW
# references linked in docs/src/psse.md. No external parser code is embedded.
const _PSSE_ORDER = [:bus,:load,:fixed_shunt,:generator,:branch,:transformer,:area,
    :two_terminal_dc,:vsc_dc,:impedance_correction,:multi_terminal_dc,:multi_section_line,
    :zone,:inter_area,:owner,:facts,:switched_shunt,:gne,:induction_machine]
const _PSSE_STRINGS=Set([:NAME,:ID,:CKT,:VECGRP,:DROOPNAME,:RMIDNT,:RSETNAM,:LOADTYPE,:DESCRIPTION,:DESC])
const _PSSE_BUSREFS=Set([:I,:J,:K,:IREG,:SWREG,:REGBUS])
const _PSSE_INTS=Set([:I,:J,:K,:IDE,:AREA,:ZONE,:OWNER,:STATUS,:STAT,:ST,:CW,:CZ,:CM,
    :NMETR,:IREG,:NREG,:BASLOD,:WMOD,:SCALE,:INTRPT,:DGENM,:BP,:MODSW,:ADJM,
    :SWREG,:MET,:O1,:O2,:O3,:O4,:IC,:REV,:XFRRAT,:NXFRAT])
_psse_fail(source,line,message)=throw(ArgumentError("$source:$line: $message"))

# Quote-aware comma or whitespace lexer. Comment slashes apply only outside
# quoted strings; doubled quotes escape quote characters. Empty CSV fields
# remain empty so defaults never shift following fields.
function _psse_tokens(line::AbstractString;source="RAW",number=0)
    chars=collect(line);pieces=String[];buf=IOBuffer();quotechar='\0';comma=false
    i=1
    while i<=length(chars)
        c=chars[i]
        if quotechar!='\0'
            if c==quotechar
                if i<length(chars)&&chars[i+1]==quotechar
                    write(buf,c);i+=1
                else
                    quotechar='\0'
                end
            else
                write(buf,c)
            end
        elseif c in ('\'', '"')
            quotechar=c
        elseif c=='/'
            break
        elseif c==','
            comma=true
        end
        i+=1
    end
    quotechar=='\0' || _psse_fail(source,number,"unterminated quoted field")
    # Second pass separates only on the selected delimiter outside quotes.
    empty!(pieces);buf=IOBuffer();quotechar='\0';i=1;started=false
    while i<=length(chars)
        c=chars[i]
        if quotechar!='\0'
            if c==quotechar
                if i<length(chars)&&chars[i+1]==quotechar
                    write(buf,c);i+=1
                else;quotechar='\0';end
            else;write(buf,c);end
        elseif c in ('\'', '"')
            quotechar=c;started=true
        elseif c=='/';break
        elseif c==',' && comma
            push!(pieces,strip(String(take!(buf))));started=false
        elseif !comma && isspace(c)
            if started;push!(pieces,strip(String(take!(buf))));started=false;end
        else
            write(buf,c);started |= !isspace(c)
        end
        i+=1
    end
    if comma || started;push!(pieces,strip(String(take!(buf))));end
    pieces
end
function _psse_number(value,source,line;integer=false)
    text=replace(strip(value),r"[dD]"=>"E")
    number=tryparse(Float64,text)
    isnothing(number) && _psse_fail(source,line,"invalid numeric field '$value'")
    isfinite(number) || _psse_fail(source,line,"nonfinite numeric field '$value'")
    if integer
        isinteger(number) && abs(number)<=typemax(Int) || _psse_fail(source,line,"integer field expected: '$value'")
        return Int(number)
    end
    number
end
function _psse_fields(tokens,names,source,line)
    result=Dict{Symbol,Any}()
    for (key,token) in zip(names,tokens)
        isempty(token) && continue
        if key in _PSSE_STRINGS || (key in _PSSE_BUSREFS && isnothing(tryparse(Float64,replace(token,r"[dD]"=>"E"))))
            result[key]=token
        else
            result[key]=_psse_number(token,source,line;integer=key in _PSSE_INTS)
        end
    end
    length(tokens)>length(names) && (result[:extra_fields]=tokens[length(names)+1:end])
    result
end
function _psse_names(section,version)
    section==:bus && return Symbol.(split("I NAME BASKV IDE AREA ZONE OWNER VM VA NVHI NVLO EVHI EVLO"))
    if section==:load
        names=split("I ID STATUS AREA ZONE PL QL IP IQ YP YQ OWNER SCALE INTRPT")
        version>=34 && append!(names,split("DGENP DGENQ DGENM"))
        version==36 && append!(names,["LOADTYPE","NAME"])
        return Symbol.(names)
    end
    section==:fixed_shunt && return (version==36 ? [:I,:ID,:STATUS,:GL,:BL,:NAME] : [:I,:ID,:STATUS,:GL,:BL])
    section==:voltage_droop && return [:NAME,:STATUS,:REGBUS,:QDB,:QMIN,:QMAX,:VDBLOW,:VDBHIGH,:VLOW,:VHIGH]
    section==:switching_rating_table && return [:RSETNAM,:DESCRIPTION,Symbol.("RATE" .* string.(1:12))...]
    section==:load_type && return [:NAME,:DESC]
    if section==:generator
        names=split("I ID PG QG QT QB VS IREG")
        version==36 && push!(names,"NREG")
        append!(names,split("MBASE ZR ZX RT XT GTAP STAT RMPCT PT PB"))
        version==36 && push!(names,"BASLOD")
        append!(names,split("O1 F1 O2 F2 O3 F3 O4 F4 WMOD WPF"))
        version==34 && push!(names,"NREG")
        version==36 && append!(names,["DROOPNAME","NAME"])
        return Symbol.(names)
    end
    if section==:branch
        names=split("I J CKT R X B")
        version==33 ? append!(names,["RATE1","RATE2","RATE3"]) :
            append!(names,["NAME";["RATE$i" for i in 1:12]])
        append!(names,split("GI BI GJ BJ ST"))
        version==36 && push!(names,"BP")
        append!(names,split("MET LEN O1 F1 O2 F2 O3 F3 O4 F4"))
        return Symbol.(names)
    end
    if section==:switched_shunt
        if version==36
            return Symbol.([split("I ID MODSW ADJM STAT VSWHI VSWLO SWREG NREG RMPCT RMIDNT BINIT NAME");
                [k for i in 1:8 for k in ("S$i","N$i","B$i")]])
        end
        names=[split("I MODSW ADJM STAT VSWHI VSWLO SWREG RMPCT RMIDNT BINIT");
            [k for i in 1:8 for k in ("N$i","B$i")]]
        version==34 && push!(names,"NREG")
        return Symbol.(names)
    end
    Symbol[]
end
function _psse_section(label)
    s=uppercase(strip(label));s=replace(s,r"\s+DATA.*$"=>"")
    aliases=Dict("SYSTEM-WIDE"=>:system_wide,"BUS"=>:bus,"LOAD"=>:load,
        "FIXED SHUNT"=>:fixed_shunt,"VOLTAGE DROOP CONTROL"=>:voltage_droop,
        "SWITCHING DEVICE RATING TABLE"=>:switching_rating_table,"SWITCHING DEVICE RATING TABLES"=>:switching_rating_table,
        "LOAD TYPE"=>:load_type,"INTERFACE"=>:interface,"INTERFACE ELEMENT"=>:interface_element,"GENERATOR"=>:generator,"BRANCH"=>:branch,
        "NON-TRANSFORMER BRANCH"=>:branch,"SYSTEM SWITCHING DEVICE"=>:system_switching_device,
        "TRANSFORMER"=>:transformer,"AREA"=>:area,"AREA INTERCHANGE"=>:area,
        "TWO-TERMINAL DC"=>:two_terminal_dc,"VSC DC LINE"=>:vsc_dc,
        "IMPEDANCE CORRECTION"=>:impedance_correction,"MULTI-TERMINAL DC"=>:multi_terminal_dc,
        "MULTI-SECTION LINE"=>:multi_section_line,"INTER-AREA TRANSFER"=>:inter_area,
        "FACTS DEVICE"=>:facts,"SWITCHED SHUNT"=>:switched_shunt,"GNE"=>:gne,
        "INDUCTION MACHINE"=>:induction_machine,"SUBSTATION"=>:substation)
    get(aliases,s,Symbol(lowercase(replace(s,r"[^A-Z0-9]+"=>"_"))))
end
function _psse_record(section,rows,lines,version,source)
    names=_psse_names(section,version)
    fields=_psse_fields(rows[1],names,source,lines[1])
    if section==:transformer
        fields=_psse_fields(rows[1],Symbol.(split("I J K CKT CW CZ CM MAG1 MAG2 NMETR NAME STAT O1 F1 O2 F2 O3 F3 O4 F4 VECGRP ZCOD")),source,lines[1])
        k=get(fields,:K,0)
        names2=k==0 ? [:R12,:X12,:SBASE12] : [:R12,:X12,:SBASE12,:R23,:X23,:SBASE23,:R31,:X31,:SBASE31,:VMSTAR,:ANSTAR]
        merge!(fields,_psse_fields(rows[2],names2,source,lines[2]))
        for w in 1:(k==0 ? 2 : 3)
            tokens=rows[w+2]
            # Two-winding secondary has only WINDV2, NOMV2.
            wn=k==0 && w==2 ? [:WINDV,:NOMV] :
                Symbol.(vcat(["WINDV","NOMV","ANG"],["RATE$i" for i in 1:(version==33 ? 3 : 12)]))
            wd=_psse_fields(tokens[1:min(length(tokens),length(wn))],wn,source,lines[w+2])
            for (key,value) in wd;fields[Symbol(string(key),"_",w)]=value;end
            # Preserve every remaining regulation/tap-control token without
            # guessing minor-version NODE field ordering.
            fields[Symbol("control_fields_",w)]=tokens[min(length(tokens),length(wn))+1:end]
        end
    end
    PSSERecord(fields,rows,lines)
end

"""Parse full-case PSS/E bus/branch RAW revisions 33, 34 and 36 from a path or IO.
Known core records have typed fields; unmodeled sections remain opaque and intact.
Errors name the source line. Omitted/empty optional fields remain absent, while
`text` preserves comments, unknown fields, quoted identifiers and original units.
Set `encoding=:latin1` for legacy extended-ASCII files (default `:utf8`).
"""
function parse_psse_raw(io::IO;source="RAW",encoding=:utf8)
    encoding in (:utf8,:latin1) || throw(ArgumentError("encoding must be :utf8 or :latin1"))
    bytes=read(io)
    text=encoding==:latin1 ? join(Char.(bytes)) : String(bytes)
    isvalid(text) || throw(ArgumentError("invalid UTF-8; use encoding=:latin1 for legacy RAW"))
    original_text=text
    text=chopprefix(text,"\ufeff")
    lines=split(text,'\n';keepempty=true)
    h=findfirst(s->!isempty(strip(s))&&!startswith(strip(s),"@!"),lines)
    isnothing(h) && throw(ArgumentError("empty RAW file"))
    tokens=_psse_tokens(lines[h];source,number=h)
    tokens_header=copy(tokens)
    length(tokens)>=3 || _psse_fail(source,h,"case header needs IC, SBASE, REV")
    ic=_psse_number(tokens[1],source,h;integer=true)
    ic==0 || _psse_fail(source,h,"change-case IC=$ic is not a standalone network")
    rev=_psse_number(tokens[3],source,h;integer=true)
    rev in (33,34,36) || _psse_fail(source,h,"unsupported RAW revision $rev; expected 33, 34 or 36")
    base=_psse_number(tokens[2],source,h);base>0 || _psse_fail(source,h,"SBASE must be positive")
    frequency=length(tokens)>=6&&!isempty(tokens[6]) ? _psse_number(tokens[6],source,h) : 60.
    frequency>0 || _psse_fail(source,h,"BASFRQ must be positive")
    h+2<=length(lines) || _psse_fail(source,h,"missing two title lines")
    titles=(rstrip(lines[h+1]),rstrip(lines[h+2]))
    order=copy(_PSSE_ORDER)
    if rev>=34;insert!(order,6,:system_switching_device);end
    if rev==36
        insert!(order,4,:voltage_droop)
        insert!(order,6,:switching_rating_table)
        append!(order,[:load_type,:interface,:interface_element])
    end
    rev>=34 && push!(order,:substation)
    sections=Dict{Symbol,Vector{PSSERecord}}();diagnostics=String[]
    section=:bus;i=h+3;seen=Set{Symbol}();terminated=false
    while i<=length(lines)
        line=strip(lines[i]);number=i;i+=1
        (isempty(line)||startswith(line,"@!")) && continue
        if uppercase(strip(first(split(line,'/';limit=2))))=="Q"
            terminated=true;break
        end
        tokens=_psse_tokens(line;source,number)
        isempty(tokens) && continue
        if section==:bus && isempty(sections) && isnothing(tryparse(Int,tokens[1]))
            section=:system_wide
        end
        delimiter=length(tokens)==1 && tryparse(Int,tokens[1])==0
        if delimiter && !(section==:substation && !isempty(get(sections,:substation,PSSERecord[])) && !occursin(r"(?i)END OF SUBSTATION",line))
            push!(seen,section)
            m=match(r"(?i)BEGIN\s+(.+?\s+DATA)",line)
            if !isnothing(m)
                nextsection=_psse_section(m.captures[1])
                nextsection in seen && _psse_fail(source,number,"repeated or reversed section $nextsection")
                section=nextsection
            elseif section==:system_wide
                section=:bus
            else
                pos=findfirst(==(section),order)
                section=isnothing(pos)||pos==length(order) ? :end_of_data : order[pos+1]
            end
            continue
        end
        section==:end_of_data && _psse_fail(source,number,"data after final section")
        rows=[tokens];numbers=[number]
        if section==:transformer
            length(tokens)>=3 || _psse_fail(source,number,"truncated transformer header")
            k=tryparse(Float64,tokens[3])
            count=isnothing(k) || k!=0 ? 5 : 4
            while length(rows)<count
                i<=length(lines) || _psse_fail(source,number,"truncated transformer record")
                entry=strip(lines[i]);ln=i;i+=1
                (isempty(entry)||startswith(entry,"@!")) && continue
                ts=_psse_tokens(entry;source,number=ln)
                (length(ts)==1 && (tryparse(Int,ts[1])==0 || uppercase(ts[1])=="Q")) &&
                    _psse_fail(source,ln,"transformer continuation missing")
                push!(rows,ts);push!(numbers,ln)
            end
        end
        push!(get!(sections,section,PSSERecord[]),_psse_record(section,rows,numbers,rev,source))
    end
    if terminated
        any(!isempty(strip(s)) && !startswith(strip(s),"@!") for s in lines[i:end]) &&
            _psse_fail(source,i,"unexpected data after Q record")
    end
    haskey(sections,:bus) || _psse_fail(source,h,"no bus data")
    # Some producers end after a final section delimiter without Q.
    !terminated && !(section in (:end_of_data,:substation) || :induction_machine in seen) &&
        _psse_fail(source,length(lines),"unexpected EOF before final section/Q record")
    for (key,records) in sections
        isempty(_psse_names(key,rev)) && key!=:transformer && push!(diagnostics,
            "$key: $(length(records)) opaque rows retained; no electrical conversion implied")
    end
    header=_psse_fields(tokens_header,[:IC,:SBASE,:REV,:XFRRAT,:NXFRAT,:BASFRQ],source,h)
    PSSERawData(rev,base,frequency,titles,header,sections,diagnostics,String(source),original_text)
end
parse_psse_raw(path::AbstractString;kwargs...)=open(io->parse_psse_raw(io;source=path,kwargs...),path,"r")

_psse_get(r,key,default)=get(r.fields,key,default)
function _psse_required(r,key,raw)
    haskey(r.fields,key) || _psse_fail(raw.source,first(r.lines),"missing required field $key")
    r.fields[key]
end
function _psse_unique(records,keys,raw)
    seen=Set{Any}()
    for r in records
        id=Tuple(k in (:ID,:CKT) ? _psse_get(r,k,"1") : k==:K ? _psse_get(r,k,0) : _psse_required(r,k,raw) for k in keys)
        id in seen && _psse_fail(raw.source,first(r.lines),"duplicate identity $id")
        push!(seen,id)
    end
end

"""Convert the representable AC subset of parsed RAW data without dropping devices.
Supplied tap ratios/phases and shunt BINIT remain fixed; automatic regulation is
retained as RAW metadata, not inferred as droop or AVR. ZIP current loads, DC,
FACTS, node/breaker topology, three-winding transformers and magnetizing models
are rejected. Zero thermal ratings require an explicit `unrated_limit` in pu.
The returned source maps preserve bus/ID and I/J/CKT identities; parsed operating
points are retained separately from clamped generator initialization hints.
"""
function import_psse_case(raw::PSSERawData;id=nothing,unrated_limit=nothing)
    isnothing(unrated_limit) || isfinite(unrated_limit)&&unrated_limit>0 || throw(ArgumentError("unrated_limit must be positive finite pu"))
    section(key)=get(raw.sections,key,PSSERecord[])
    diagnostics=copy(raw.diagnostics)
    all(get(raw.header,k,0)==0 for k in (:XFRRAT,:NXFRAT)) || throw(ArgumentError("current-based RAW rating units are preserved but AC conversion requires MVA ratings"))
    supported=Set([:bus,:load,:fixed_shunt,:generator,:branch,:transformer,:switched_shunt,
        :system_wide,:area,:zone,:inter_area,:owner,:multi_section_line,:load_type])
    for key in keys(raw.sections)
        key in supported || isempty(section(key)) || throw(ArgumentError("$key records are preserved but unsupported for AC conversion"))
    end
    for key in (:two_terminal_dc,:vsc_dc,:multi_terminal_dc,:facts,:gne,:induction_machine,:substation,:system_switching_device,:impedance_correction)
        isempty(section(key)) || throw(ArgumentError("$key records are preserved but cannot be converted to this AC model"))
    end
    for key in (:bus,:load,:fixed_shunt,:generator,:branch,:transformer,:switched_shunt), r in section(key), field in (:I,:J,:K)
        get(r.fields,field,0) isa Integer || _psse_fail(raw.source,first(r.lines),
            "extended bus-name references are retained by the parser; AC conversion requires numeric bus IDs")
    end
    for (key,keys) in [(:bus,[:I]),(:load,[:I,:ID]),(:fixed_shunt,[:I,:ID]),(:generator,[:I,:ID]),(:branch,[:I,:J,:CKT]),(:transformer,[:I,:J,:K,:CKT])]
        _psse_unique(section(key),keys,raw)
    end
    for (key,status) in [(:load,:STATUS),(:fixed_shunt,:STATUS),(:generator,:STAT),(:branch,:ST),(:switched_shunt,:STAT)]
        for r in section(key)
            _psse_get(r,status,1) in (0,1) || _psse_fail(raw.source,first(r.lines),"invalid $key status")
        end
    end
    _psse_unique(section(:switched_shunt),raw.revision==36 ? [:I,:ID] : [:I],raw)
    buses=Bus[];loads=Load[];generators=Generator[];branches=Branch[];shunts=FixedShunt[]
    source_ids=Dict(k=>Dict{Int,Any}() for k in (:bus,:load,:generator,:branch,:shunt))
    allbus=Dict(Int(_psse_required(r,:I,raw))=>r for r in section(:bus))
    active=Set(i for (i,r) in allbus if _psse_get(r,:IDE,1)!=4)
    for r in section(:bus)
        i=Int(_psse_required(r,:I,raw));ide=_psse_get(r,:IDE,1)
        ide in 1:4 || _psse_fail(raw.source,first(r.lines),"unsupported bus IDE=$ide")
        if i in active
            push!(buses,Bus(i;reference=ide==3,v_min=_psse_get(r,:NVLO,.9),v_max=_psse_get(r,:NVHI,1.1)))
            source_ids[:bus][i]=i
        else
            push!(diagnostics,"isolated bus $i (IDE=4) excluded from energized AC network")
        end
    end
    count(b.reference for b in buses)==1 || throw(ArgumentError("AC conversion requires exactly one energized reference bus; RAW data remain available"))
    function buscheck(i,r)
        haskey(allbus,i) || _psse_fail(raw.source,first(r.lines),"unknown bus $i")
        i in active
    end
    function shunt!(i,g,b,available,identity)
        sid=length(shunts)+1
        push!(shunts,FixedShunt(sid,i;conductance=g,susceptance=b,available))
        source_ids[:shunt][sid]=identity
    end
    for r in section(:load)
        i=Int(_psse_required(r,:I,raw));buscheck(i,r)||continue
        _psse_get(r,:STATUS,1)==0 && continue
        any(!iszero(_psse_get(r,k,0.)) for k in (:IP,:IQ,:DGENP,:DGENQ)) &&
            _psse_fail(raw.source,first(r.lines),"current ZIP or embedded generation load model is unsupported")
        lid=length(loads)+1
        push!(loads,Load(lid,i;p=_psse_get(r,:PL,0.)/raw.base_power,q=_psse_get(r,:QL,0.)/raw.base_power))
        identity=(i,_psse_get(r,:ID,"1"));source_ids[:load][lid]=identity
        yp=_psse_get(r,:YP,0.);yq=_psse_get(r,:YQ,0.)
        if yp!=0 || yq!=0
            shunt!(i,yp/raw.base_power,-yq/raw.base_power,true,(:load_impedance,identity))
        end
    end
    for r in section(:fixed_shunt)
        i=Int(_psse_required(r,:I,raw));buscheck(i,r)||continue
        shunt!(i,_psse_get(r,:GL,0.)/raw.base_power,_psse_get(r,:BL,0.)/raw.base_power,
            _psse_get(r,:STATUS,1)!=0,(:fixed,i,_psse_get(r,:ID,"1")))
    end
    for r in section(:switched_shunt)
        i=Int(_psse_required(r,:I,raw));buscheck(i,r)||continue
        shunt!(i,0.,_psse_get(r,:BINIT,0.)/raw.base_power,_psse_get(r,:STAT,1)!=0,
            (:switched_initial,i,_psse_get(r,:ID,"1")))
        push!(diagnostics,"switched shunt at $i locked at supplied BINIT; switching/regulation not imported")
    end
    supplied_pg=Float64[];supplied_qg=Float64[]
    for r in section(:generator)
        i=Int(_psse_required(r,:I,raw));buscheck(i,r)||continue
        gid=length(generators)+1;available=_psse_get(r,:STAT,1)!=0
        p=_psse_get(r,:PG,0.)/raw.base_power;q=_psse_get(r,:QG,0.)/raw.base_power
        pmin=_psse_get(r,:PB,-9999.)/raw.base_power;pmax=_psse_get(r,:PT,9999.)/raw.base_power
        qmin=_psse_get(r,:QB,-9999.)/raw.base_power;qmax=_psse_get(r,:QT,9999.)/raw.base_power
        push!(generators,Generator(gid,i;available,p_min=pmin,p_max=pmax,q_min=qmin,q_max=qmax,
            initial_p=clamp(p,pmin,pmax),initial_q=clamp(q,qmin,qmax)))
        push!(supplied_pg,p);push!(supplied_qg,q)
        (pmin<=p<=pmax && qmin<=q<=qmax) || push!(diagnostics,"generator $i/$(_psse_get(r,:ID,"1")) supplied P/Q outside limits; only optimizer start hint clamped")
        source_ids[:generator][gid]=(i,_psse_get(r,:ID,"1"))
    end
    function rating(value,r)
        value>=0 || _psse_fail(raw.source,first(r.lines),"negative thermal rating")
        if value==0
            isnothing(unrated_limit) && _psse_fail(raw.source,first(r.lines),"zero/omitted thermal rating; supply explicit unrated_limit (pu)")
            push!(diagnostics,"explicit unrated_limit=$unrated_limit pu used at line $(first(r.lines))")
            return Float64(unrated_limit)
        end
        value/raw.base_power
    end
    for r in section(:branch)
        i=abs(Int(_psse_required(r,:I,raw)));j=abs(Int(_psse_required(r,:J,raw)))
        a=buscheck(i,r);b=buscheck(j,r);a&&b||continue
        _psse_get(r,:BP,0)==0 || _psse_fail(raw.source,first(r.lines),"bypassed branch cannot be converted without zero-impedance topology reduction")
        any(!iszero(_psse_get(r,k,0.)) for k in (:GI,:BI,:GJ,:BJ)) &&
            _psse_fail(raw.source,first(r.lines),"branch-end shunts unsupported; cannot preserve their outage association")
        bid=length(branches)+1
        push!(branches,Branch(bid,i,j;resistance=_psse_required(r,:R,raw),reactance=_psse_required(r,:X,raw),
            charging=_psse_get(r,:B,0.),thermal_limit=rating(_psse_get(r,:RATE1,0.),r),available=_psse_get(r,:ST,1)!=0))
        source_ids[:branch][bid]=(:line,i,j,_psse_get(r,:CKT,"1"))
    end
    for r in section(:transformer)
        i=Int(_psse_required(r,:I,raw));j=Int(_psse_required(r,:J,raw))
        a=buscheck(i,r);b=buscheck(j,r);a&&b||continue
        _psse_get(r,:STAT,1) in (0,1) || _psse_fail(raw.source,first(r.lines),"invalid two-winding transformer status")
        _psse_get(r,:K,0)==0 || _psse_fail(raw.source,first(r.lines),"three-winding transformer conversion unsupported")
        any(!iszero(_psse_get(r,k,0.)) for k in (:MAG1,:MAG2)) &&
            _psse_fail(raw.source,first(r.lines),"transformer magnetizing admittance conversion unsupported")
        cw=_psse_get(r,:CW,1);cz=_psse_get(r,:CZ,1)
        z=complex(_psse_required(r,:R12,raw),_psse_required(r,:X12,raw));sbase=_psse_get(r,:SBASE12,raw.base_power)
        cz==1 || sbase>0 || _psse_fail(raw.source,first(r.lines),"transformer SBASE12 must be positive")
        if cz==2;z*=raw.base_power/sbase
        elseif cz==3
            resistance=real(z)/(1e6*sbase);magnitude=imag(z)
            magnitude>=abs(resistance) || _psse_fail(raw.source,first(r.lines),"invalid transformer load loss / impedance magnitude")
            z=complex(resistance,sqrt(magnitude^2-resistance^2))*raw.base_power/sbase
        elseif cz!=1;_psse_fail(raw.source,first(r.lines),"unsupported transformer CZ=$cz");end
        kv1=_psse_get(allbus[i],:BASKV,0.);kv2=_psse_get(allbus[j],:BASKV,0.)
        function ratio(w,kv)
            value=_psse_get(r,Symbol("WINDV_",w),cw==2 ? kv : 1.)
            if cw==1;return value
            elseif cw==2
                kv>0 || _psse_fail(raw.source,first(r.lines),"positive bus base kV required for CW=2")
                return value/kv
            elseif cw==3
                nom=_psse_get(r,Symbol("NOMV_",w),0.);nom=nom==0 ? kv : nom
                kv>0&&nom>0 || _psse_fail(raw.source,first(r.lines),"positive nominal and bus kV required for CW=3")
                return value*nom/kv
            end
            _psse_fail(raw.source,first(r.lines),"unsupported transformer CW=$cw")
        end
        if cz!=1
            nom1=_psse_get(r,:NOMV_1,0.)
            if nom1!=0
                kv1>0 || _psse_fail(raw.source,first(r.lines),"positive bus kV required for impedance base conversion")
                z*=(nom1/kv1)^2
            end
        end
        tap1=ratio(1,kv1);tap2=ratio(2,kv2)
        tap1>0&&tap2>0 || _psse_fail(raw.source,first(r.lines),"transformer winding ratio must be positive")
        # Moving the secondary ratio into the from-side primitive scales series
        # impedance by tap2², in addition to the effective tap1/tap2 ratio.
        z*=tap2^2
        bid=length(branches)+1
        push!(branches,Branch(bid,i,j;resistance=real(z),reactance=imag(z),
            thermal_limit=rating(_psse_get(r,:RATE1_1,0.),r),available=_psse_get(r,:STAT,1)!=0,
            tap_ratio=tap1/tap2,phase_shift=deg2rad(_psse_get(r,:ANG_1,0.)),kind=:transformer))
        source_ids[:branch][bid]=(:transformer,i,j,_psse_get(r,:CKT,"1"))
    end
    c=Case(isnothing(id) ? splitext(basename(raw.source))[1] : String(id);
        base_power=raw.base_power,base_frequency=raw.base_frequency,
        network=ACNetwork(buses,branches;shunts),loads,generators,
        controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    reference=only(b.id for b in buses if b.reference)
    shift=deg2rad(_psse_get(allbus[reference],:VA,0.))
    state=ACState([_psse_get(allbus[b.id],:VM,1.) for b in buses],
        [deg2rad(_psse_get(allbus[b.id],:VA,0.))-shift for b in buses],supplied_pg,supplied_qg)
    push!(diagnostics,"RAW voltage regulation, ownership and interchange metadata retained; no automatic droop/AVR inferred")
    PSSEImport(c,state,source_ids,diagnostics,raw)
end
"""Load the strict supported PSS/E RAW AC subset as a `Case`; use
`import_psse_case(parse_psse_raw(path))` for source identities and diagnostics.
Unrated branches require an explicit `unrated_limit` (pu). Saved-state checking
runs automatically and warns on failure; `require_valid=true` rejects a failed
check. `report_path` optionally writes JSON. Use `validation_options=(;...)`
for tolerances, or explicit `check_saved_solution=false` to disable checking.
For report-only checks of unrated/unsupported files, use `check_psse_file`.
"""
function load_psse_case(path::AbstractString;encoding=:utf8,check_saved_solution=true,
    report_path=nothing,require_valid=false,validation_options=(;),kwargs...)
    require_valid&&!check_saved_solution && throw(ArgumentError("require_valid needs saved-solution checking"))
    !check_saved_solution&&!isnothing(report_path) && throw(ArgumentError("report_path needs saved-solution checking"))
    _psse_report_destination(path,report_path)
    imported=import_psse_case(parse_psse_raw(path;encoding);kwargs...)
    if check_saved_solution
        report=validate_psse_saved_solution(imported;validation_options...)
        report["source_file_sha256"]=bytes2hex(SHA.sha256(read(path)))
        isnothing(report_path)||write_psse_validation_report(report_path,report)
        _psse_validation_notice(report)
        require_valid&&!report["valid"] && throw(ArgumentError("saved PSS/E solution failed validation: $(report["status"]); inspect the validation report"))
    end
    imported.case
end
