# A sparse outer LP with independently replayable rational Farkas certificates.
# Phase-shifting and selected equipment are rejected explicitly in this verifier.
const _FR = Rational{BigInt}
mutable struct _FeasibilityLP
    bounds::Vector{Tuple{_FR,_FR}}
    rows::Vector{Tuple{Dict{Int,_FR},_FR}}
    v::Vector{Int}
    w::Vector{Int}
    wr::Vector{Int}
    wi::Vector{Int}
    edges::Vector{Tuple{Int,Int}}
    flows::Vector{Tuple{Dict{Int,_FR},Dict{Int,_FR},_FR}}
    cliques::Vector{Vector{Int}}
    products::Dict{Tuple{Int,Int},Tuple{Int,Int,Int}}
    psd_clique_limit::Int
end
# Keep the original constructor for old ledgers and small arithmetic tests.
_FeasibilityLP(bounds,rows,v,w,wr,wi,edges,flows)=_FeasibilityLP(bounds,rows,v,w,wr,wi,edges,flows,
    Vector{Int}[],Dict{Tuple{Int,Int},Tuple{Int,Int,Int}}(),0)

function _flp_cycle_extension!(d,limit)
    d.psd_clique_limit=limit
    limit==0 && return d
    n=length(d.v);adj=[Set{Int}() for _ in 1:n]
    # Parallel circuits describe the same bus-voltage product, even when their
    # tap ratios differ. Opposite orientations conjugate the imaginary part.
    for (k,(i,j)) in enumerate(d.edges)
        i==j && throw(ArgumentError("cycle relaxation does not support self-loop branches"))
        a,b=minmax(i,j);sgn=i==a ? 1 : -1
        if haskey(d.products,(a,b))
            wr,wi,orientation=d.products[(a,b)]
            _flp_eq!(d,_flp_aff([d.wr[k]=>1,wr=>-1]),0)
            _flp_eq!(d,_flp_aff([d.wi[k]=>sgn,wi=>-orientation]),0)
        else
            d.products[(a,b)]=(d.wr[k],d.wi[k],sgn)
        end
        push!(adj[i],j);push!(adj[j],i)
    end
    active=Set(1:n)
    while !isempty(active)
        i=first(sort!(collect(active);by=i->(length(adj[i]),i)))
        neighbors=sort!(collect(adj[i]))
        # Bound clique size and fill growth; the remaining core is deliberately
        # left relaxed rather than creating a dense network-wide PSD block.
        length(neighbors)+1>limit && break
        clique=sort!([i;neighbors])
        length(clique)>=3 && push!(d.cliques,clique)
        for aidx in eachindex(neighbors),bidx in aidx+1:length(neighbors)
            a,b=neighbors[aidx],neighbors[bidx]
            if !haskey(d.products,(a,b))
                bound=last(d.bounds[d.v[a]])*last(d.bounds[d.v[b]])
                wr=_flp_var!(d,-bound,bound);wi=_flp_var!(d,-bound,bound)
                push!(d.edges,(a,b));push!(d.wr,wr);push!(d.wi,wi)
                d.products[(a,b)]=(wr,wi,1)
            end
            push!(adj[a],b);push!(adj[b],a)
        end
        for j in neighbors
            delete!(adj[j],i)
        end
        delete!(active,i)
    end
    d
end

function _flp_psd_row(d,cut)
    nodes=Int.(cut["nodes"])
    nodes in d.cliques || throw(ArgumentError("PSD cut is not on a reconstructed clique"))
    a=_flp_parse.(cut["real"]);b=_flp_parse.(cut["imag"])
    length(a)==length(b)==length(nodes) || throw(ArgumentError("invalid PSD cut vector"))
    terms=Pair{Int,_FR}[]
    # -z'*W*z <= 0 is valid for every physical W=V*V', for any rational z.
    for k in eachindex(nodes)
        push!(terms,d.w[nodes[k]]=>-(a[k]^2+b[k]^2))
        for l in k+1:length(nodes)
            wr,wi,orientation=d.products[(nodes[k],nodes[l])]
            push!(terms,wr=>-2(a[k]*a[l]+b[k]*b[l]))
            push!(terms,wi=>-2orientation*(b[k]*a[l]-a[k]*b[l]))
        end
    end
    _flp_aff(terms)
end
function _flp_psd_cuts(d,x;tol=1e-8)
    cuts=Dict{String,Any}[]
    for nodes in d.cliques
        m=length(nodes);matrix=zeros(ComplexF64,m,m)
        for k in 1:m
            matrix[k,k]=x[d.w[nodes[k]]]
            for l in k+1:m
                wr,wi,orientation=d.products[(nodes[k],nodes[l])]
                matrix[k,l]=complex(x[wr],orientation*x[wi]);matrix[l,k]=conj(matrix[k,l])
            end
        end
        eig=eigen(Hermitian(matrix))
        for k in findall(v->v < -tol,eig.values)
            z=eig.vectors[:,k]
            # Quantization controls proof size. Any vector remains a valid PSD
            # support plane, so eigenvectors need no trusted numerical proof.
            quant(v)=string(round(BigInt,v*2.0^24)//big(2)^24)
            cut=Dict{String,Any}("kind"=>"psd","nodes"=>nodes,
                "real"=>quant.(real.(z)),"imag"=>quant.(imag.(z)))
            row=_flp_psd_row(d,cut)
            sum(Float64(v)*x[i] for (i,v) in row)>tol && push!(cuts,cut)
        end
    end
    cuts
end
_flp_var!(d,l,u)=(push!(d.bounds,(_fq(l),_fq(u)));length(d.bounds))
function _flp_aff(terms)
    a=Dict{Int,_FR}()
    for (i,x) in terms
        a[i]=get(a,i,_fq(0))+_fq(x)
    end
    filter!(p->!iszero(last(p)),a);a
end
_flp_row!(d,a,b)=(push!(d.rows,(a,_fq(b)));nothing)
function _flp_eq!(d,a,b;tol=0)
    _flp_row!(d,a,_fq(b)+_fq(tol))
    _flp_row!(d,Dict(i=>-x for (i,x) in a),-_fq(b)+_fq(tol))
end
function _flp_combine(terms)
    _flp_aff((i=>scale*x for (a,scale) in terms for (i,x) in a))
end
function _feasibility_lp(p;voltage_bounds=nothing,psd_clique_limit=0)
    (psd_clique_limit==0 || 3<=psd_clique_limit<=32) || throw(ArgumentError("PSD clique limit must be zero or between 3 and 32"))
    feasibility_fingerprint(p);c=p.case;t=p.tolerances
    isempty(p.tap_controls) && isempty(p.shunt_controls) || throw(ArgumentError("rational LP certificate requires fixed equipment"))
    all(b.phase_shift==0 for b in c.network.branches if b.available) || throw(ArgumentError("rational LP certificate currently requires zero phase shifts"))
    d=_FeasibilityLP(Tuple{_FR,_FR}[],Tuple{Dict{Int,_FR},_FR}[],Int[],Int[],Int[],Int[],Tuple{Int,Int}[],Tuple{Dict{Int,_FR},Dict{Int,_FR},_FR}[])
    idx=_bus_indices(c.network);z=_fq(0);oneq=_fq(1)
    for (i,b) in enumerate(c.network.buses)
        l=max(z,_fq(b.v_min)-_fq(t.limit_tolerance));u=_fq(b.v_max)+_fq(t.limit_tolerance)
        if !isnothing(voltage_bounds)
            l,u=voltage_bounds[i]
        end
        push!(d.v,_flp_var!(d,l,u));push!(d.w,_flp_var!(d,l^2,u^2))
        v=last(d.v);w=last(d.w)
        _flp_row!(d,_flp_aff([w=>oneq,v=>-(l+u)]),-l*u)
        for a in (l,(l+u)/2,u)
            _flp_row!(d,_flp_aff([v=>2a,w=>-oneq]),a^2)
        end
    end
    pg=Int[];qg=Int[]
    for g in c.generators
        l,u=_feasibility_p_interval(p,g);push!(pg,_flp_var!(d,l,u))
        l,u=g.available ? (_fq(g.q_min)-_fq(t.limit_tolerance),_fq(g.q_max)+_fq(t.limit_tolerance)) :
            (-_fq(t.unavailable_tolerance),_fq(t.unavailable_tolerance))
        push!(qg,_flp_var!(d,l,u))
    end
    pflows=[Pair{Int,_FR}[] for _ in c.network.buses]
    qflows=[Pair{Int,_FR}[] for _ in c.network.buses]
    directions=[(1//1,0//1),(0//1,1//1),(3//5,4//5),(4//5,3//5)]
    for b in c.network.branches
        b.available || continue
        i,j=idx[b.from_bus],idx[b.to_bus];push!(d.edges,(i,j))
        bound=last(d.bounds[d.v[i]])*last(d.bounds[d.v[j]])
        wr=_flp_var!(d,-bound,bound);wi=_flp_var!(d,-bound,bound)
        push!(d.wr,wr);push!(d.wi,wi)
        # Initial valid SOC support planes.
        for (a,bb) in directions,sa in (-1,1),sb in (-1,1)
            _flp_row!(d,_flp_aff([wr=>2sa*a,wi=>2sb*bb,d.w[i]=>-oneq,d.w[j]=>-oneq]),z)
        end
        r,x,tau,ch=_fq(b.resistance),_fq(b.reactance),_fq(b.tap_ratio),_fq(b.charging)
        g=r/(r^2+x^2);bb=-x/(r^2+x^2)
        pf=_flp_aff([d.w[i]=>g/tau^2,wr=>-g/tau,wi=>-bb/tau])
        qf=_flp_aff([d.w[i]=>-(bb+ch/2)/tau^2,wr=>bb/tau,wi=>-g/tau])
        pt=_flp_aff([d.w[j]=>g,wr=>-g/tau,wi=>bb/tau])
        qt=_flp_aff([d.w[j]=>-(bb+ch/2),wr=>bb/tau,wi=>g/tau])
        append!(pflows[i],collect(pf));append!(pflows[j],collect(pt))
        append!(qflows[i],collect(qf));append!(qflows[j],collect(qt))
        rate=_fq(b.thermal_limit)+_fq(t.limit_tolerance)
        for (pp,qq) in ((pf,qf),(pt,qt))
            push!(d.flows,(pp,qq,rate))
            for (a,bb) in directions,sa in (-1,1),sb in (-1,1)
                _flp_row!(d,_flp_combine([(pp,sa*a),(qq,sb*bb)]),rate)
            end
        end
    end
    for (i,bus) in enumerate(c.network.buses)
        pa=Pair{Int,_FR}[pg[k]=>oneq for (k,g) in enumerate(c.generators) if g.bus_id==bus.id]
        qa=Pair{Int,_FR}[qg[k]=>oneq for (k,g) in enumerate(c.generators) if g.bus_id==bus.id]
        append!(pa,[k=>-v for (k,v) in pflows[i]]);append!(qa,[k=>-v for (k,v) in qflows[i]])
        gsum=bsum=z
        for s in c.network.shunts
            s.available && s.bus_id==bus.id || continue
            gsum+=_fq(s.conductance);bsum+=_fq(s.susceptance)
        end
        for bank in c.network.banks
            bank.available && bank.bus_id==bus.id || continue
            gsum+=sum((_fq(n)*_fq(g) for (n,g) in zip(bank.state,bank.step_conductances));init=z)
            bsum+=sum((_fq(n)*_fq(b) for (n,b) in zip(bank.state,bank.step_susceptances));init=z)
        end
        push!(pa,d.w[i]=>-gsum);push!(qa,d.w[i]=>bsum)
        pd=sum((_fq(l.p) for l in c.loads if l.bus_id==bus.id);init=z)
        qd=sum((_fq(l.q) for l in c.loads if l.bus_id==bus.id);init=z)
        _flp_eq!(d,_flp_aff(pa),pd;tol=t.power_tolerance)
        _flp_eq!(d,_flp_aff(qa),qd;tol=t.power_tolerance)
    end
    gi=Dict(g.id=>i for (i,g) in enumerate(c.generators))
    for a in c.attachments
        g=gi[a.generator_id];c.generators[g].available || continue
        i=idx[a.location.bus_id];control=c.controls[a.control_id];l,u=d.bounds[d.v[i]]
        xs=sort!(unique([l;[x for x in _fq.(droop_curve(control).breakpoints) if l<x<u];u]))
        ys=[_feasibility_curve_value(control,x) for x in xs]
        lambda=[_flp_var!(d,z,oneq) for _ in xs]
        _flp_eq!(d,_flp_aff([k=>oneq for k in lambda]),oneq)
        _flp_eq!(d,_flp_aff([d.v[i]=>oneq;[lambda[k]=>-xs[k] for k in eachindex(xs)]]),z)
        _flp_eq!(d,_flp_aff([qg[g]=>oneq;[lambda[k]=>-ys[k] for k in eachindex(xs)]]),z;tol=t.droop_tolerance)
    end
    _flp_cycle_extension!(d,psd_clique_limit)
end
function _flp_parse(s)
    parts=split(s,"//")
    length(parts)==2 || throw(ArgumentError("invalid rational certificate number"))
    parse(BigInt,parts[1])//parse(BigInt,parts[2])
end
function _flp_cut!(d,cut)
    kind=cut["kind"];z=_fq(0)
    if kind=="psd"
        _flp_row!(d,_flp_psd_row(d,cut),z);return
    end
    i=Int(cut["index"])
    if kind=="voltage"
        a=_flp_parse(cut["at"])
        _flp_row!(d,_flp_aff([d.v[i]=>2a,d.w[i]=>-_fq(1)]),a^2)
    elseif kind=="edge"
        a,b,c=_flp_parse.(cut["direction"])
        a^2+b^2+c^2<=1 || throw(ArgumentError("invalid SOC support direction"))
        f,t=d.edges[i]
        _flp_row!(d,_flp_aff([d.wr[i]=>2a,d.wi[i]=>2b,d.w[f]=>c-1,d.w[t]=>-c-1]),z)
    elseif kind=="thermal"
        a,b=_flp_parse.(cut["direction"])
        a^2+b^2<=1 || throw(ArgumentError("invalid thermal support direction"))
        p,q,s=d.flows[i];_flp_row!(d,_flp_combine([(p,a),(q,b)]),s)
    else
        throw(ArgumentError("unknown outer-relaxation cut"))
    end
end
function _flp_direction(values)
    mag=sqrt(sum(abs2,values));mag>0 || return nothing
    q=_fq.(values./mag);n2=sum(abs2,q)
    n2>1 && (q=q./n2)
    string.(q)
end
function _flp_separate(d,x;tol=1e-8)
    cuts=Dict{String,Any}[]
    for i in eachindex(d.v)
        x[d.v[i]]^2-x[d.w[i]]>tol && push!(cuts,Dict("kind"=>"voltage","index"=>i,"at"=>string(_fq(x[d.v[i]]))))
    end
    for (k,(i,j)) in enumerate(d.edges)
        vec=[2x[d.wr[k]],2x[d.wi[k]],x[d.w[i]]-x[d.w[j]]]
        sqrt(sum(abs2,vec))-(x[d.w[i]]+x[d.w[j]])>tol &&
            push!(cuts,Dict("kind"=>"edge","index"=>k,"direction"=>_flp_direction(vec)))
    end
    for (k,(p,q,s)) in enumerate(d.flows)
        pf=sum(Float64(v)*x[i] for (i,v) in p);qf=sum(Float64(v)*x[i] for (i,v) in q)
        hypot(pf,qf)-Float64(s)>tol && push!(cuts,Dict("kind"=>"thermal","index"=>k,"direction"=>_flp_direction([pf,qf])))
    end
    append!(cuts,_flp_psd_cuts(d,x;tol))
    cuts
end
function _flp_margin(d,multipliers;objective_index=nothing,objective_sign=1)
    total=fill(_fq(0),length(d.bounds));rhs=_fq(0)
    isnothing(objective_index) || (total[objective_index]=_fq(objective_sign))
    for pair in multipliers
        row=Int(pair[1]);y=_flp_parse(pair[2]);y>=0 || throw(ArgumentError("negative Farkas multiplier"))
        a,b=d.rows[row];rhs+=y*b
        for (i,v) in a
            total[i]+=y*v
        end
    end
    sum(min(total[i]*l,total[i]*u) for (i,(l,u)) in enumerate(d.bounds))-rhs
end
function _flp_apply_bound!(d,proof)
    i=Int(proof["index"]);sign=Int(proof["sign"])
    sign in (-1,1) || throw(ArgumentError("invalid bound objective sign"))
    bound=_flp_margin(d,proof["multipliers"];objective_index=d.v[i],objective_sign=sign)
    string(bound)==proof["lower_bound_exact"] || throw(ArgumentError("bound proof does not replay"))
    lo,hi=d.bounds[d.v[i]]
    # Round outwards to a fixed dyadic grid before rebuilding envelopes. This
    # keeps repeated rational bound propagation from growing denominators.
    grid=big(2)^32
    lower=floor(BigInt,bound*grid)//grid
    upper=ceil(BigInt,-bound*grid)//grid
    d.bounds[d.v[i]]=sign==1 ? (max(lo,min(hi,lower)),hi) : (lo,min(hi,max(lo,upper)))
end
function _flp_rebuild_after_stage(p,d,stage)
    foreach(cut->_flp_cut!(d,cut),stage["cuts"])
    foreach(proof->_flp_apply_bound!(d,proof),stage["bounds"])
    _feasibility_lp(p;voltage_bounds=[d.bounds[i] for i in d.v],psd_clique_limit=d.psd_clique_limit)
end
function _verify_feasibility_lp_certificate(p,cert)
    try
        cert["method"]=="rational_sparse_outer_lp" || return false
        d=_feasibility_lp(p;psd_clique_limit=get(cert,"psd_clique_limit",0))
        for stage in get(cert,"bound_stages",[])
            d=_flp_rebuild_after_stage(p,d,stage)
        end
        foreach(cut->_flp_cut!(d,cut),cert["cuts"])
        margin=_flp_margin(d,cert["multipliers"])
        margin>0 && string(margin)==cert["strict_gap_exact"]
    catch e
        e isa InterruptException && rethrow()
        false
    end
end

"""Replay every LP weak-duality bound proof and return outward-rounded voltage bounds.

This never trusts the ledger's displayed bounds. Bounds from the original
strict problem must not be reused as bounds on a voltage-relaxed problem.
"""
function verified_feasibility_voltage_bounds(p::FeasibilityProblem,r::FeasibilityResult)
    feasibility_fingerprint(p)==r.fingerprint || throw(ArgumentError("bound evidence has a different scope"))
    attempts=[a for a in r.attempts if get(a,"stage",nothing)=="verified_outer_lp" && haskey(a,"verified_bound_stages")]
    isempty(attempts) && throw(ArgumentError("result contains no voltage-bound evidence"))
    d=_feasibility_lp(p;psd_clique_limit=get(last(attempts),"psd_clique_limit",0))
    for stage in last(attempts)["verified_bound_stages"]
        d=_flp_rebuild_after_stage(p,d,stage)
    end
    Dict(b.id=>(_flp_round(d.bounds[d.v[i]][1],false),_flp_round(d.bounds[d.v[i]][2],true))
        for (i,b) in enumerate(p.case.network.buses))
end
function _flp_round(r,up)
    f=Float64(r);isfinite(f) || throw(ArgumentError("LP coefficient exceeds Float64 range"))
    up ? (_fq(f)<r ? nextfloat(f) : f) : (_fq(f)>r ? prevfloat(f) : f)
end
function _flp_solver_row!(model,x,d,row)
    a,b=row;rhs=b;expr=AffExpr(0.)
    for (i,v) in a
        f=Float64(v);isfinite(f) || throw(ArgumentError("nonfinite LP coefficient"))
        add_to_expression!(expr,f,x[i])
        error=_fq(f)-v;l,u=d.bounds[i];rhs+=max(error*l,error*u)
    end
    # Outward rounding retains every exact feasible point of the rational LP.
    @constraint(model,expr<=_flp_round(rhs,true))
end

"""Try a sparse outer LP and return only independently verified infeasibility.

The optional LP solver supplies candidate Farkas multipliers. The checker uses
exact rational arithmetic, including residual stationarity errors over finite
variable bounds. SOC/thermal tangent cuts are independently validated. Optional `psd_clique_limit`
(0 disables; 3–32 enables) adds bounded-size cycle PSD support cuts, whose rational
coefficients are reconstructed independently. Feasible
LP points never qualify the original nonconvex problem. The work is bounded by
`time_limit` and `max_rounds`; no global solver is required by the main package.
"""
function certify_feasibility_lp(p::FeasibilityProblem;optimizer_factory,time_limit=30.,max_rounds=30,
    bound_tightening_rounds=0,bound_bus_limit=16,bound_cut_rounds=5,psd_clique_limit=0)
    isfinite(time_limit) && time_limit>0 && max_rounds>0 && bound_tightening_rounds>=0 && bound_bus_limit>0 && bound_cut_rounds>=0 ||
        throw(ArgumentError("invalid LP certification budget"))
    start=time();d=_feasibility_lp(p;psd_clique_limit)
    cuts=Dict{String,Any}[];history=Dict{String,Any}[];certificate=nothing;stages=Dict{String,Any}[]
    for level in 0:bound_tightening_rounds
        model=Model(optimizer_factory);set_silent(model)
        @variable(model,_flp_round(d.bounds[i][1],false)<=x[i=1:length(d.bounds)]<=_flp_round(d.bounds[i][2],true))
        @objective(model,Min,0.)
        refs=[_flp_solver_row!(model,x,d,row) for row in d.rows]
        cuts=Dict{String,Any}[];seen=Set{String}()
        for round in 1:max_rounds
            remaining=time_limit-(time()-start);remaining>0 || break
            set_time_limit_sec(model,remaining);optimize!(model)
            record=Dict{String,Any}("level"=>level,"round"=>round,"rows"=>length(d.rows),"status"=>string(termination_status(model)))
            push!(history,record)
            if dual_status(model)==JuMP.MOI.INFEASIBILITY_CERTIFICATE
                ys=dual.(refs)
                if all(isfinite,ys)
                    multipliers=Any[[i,string(_fq(-y))] for (i,y) in enumerate(ys) if y<0]
                    margin=_flp_margin(d,multipliers);record["verified_gap_exact"]=string(margin)
                    if margin>0
                        certificate=Dict{String,Any}("method"=>"rational_sparse_outer_lp","psd_clique_limit"=>psd_clique_limit,
                            "arithmetic"=>"exact rational, including multiplier residual correction",
                            "bound_stages"=>deepcopy(stages),"cuts"=>deepcopy(cuts),"multipliers"=>multipliers,
                            "strict_gap_exact"=>string(margin),
                            "omitted_constraints"=>"angle windows, rank-one consistency, unseparated PSD constraints, droop-region adjacency")
                        break
                    end
                end
            end
            has_values(model) || break
            newcuts=filter(cut->!(_feasibility_canonical(cut) in seen),_flp_separate(d,value.(x)))
            record["cuts_added"]=length(newcuts)
            isempty(newcuts) && break
            for cut in newcuts
                push!(seen,_feasibility_canonical(cut))
                _flp_cut!(d,cut);push!(cuts,cut);push!(refs,_flp_solver_row!(model,x,d,last(d.rows)))
            end
        end
        !isnothing(certificate) && break
        level==bound_tightening_rounds && break
        time()-start<time_limit || break
        bounds=Dict{String,Any}[]
        for i in 1:min(length(d.v),bound_bus_limit),sign in (1,-1)
            remaining=time_limit-(time()-start);remaining>0 || break
            @objective(model,Min,sign*x[d.v[i]])
            for cut_round in 0:bound_cut_rounds
                remaining=time_limit-(time()-start);remaining>0 || break
                set_time_limit_sec(model,remaining);optimize!(model)
                cut_round==bound_cut_rounds && break
                has_values(model) || break
                newcuts=filter(cut->!(_feasibility_canonical(cut) in seen),_flp_separate(d,value.(x)))
                isempty(newcuts) && break
                for cut in newcuts
                    push!(seen,_feasibility_canonical(cut));_flp_cut!(d,cut);push!(cuts,cut)
                    push!(refs,_flp_solver_row!(model,x,d,last(d.rows)))
                end
            end
            has_duals(model) || continue
            ys=dual.(refs);all(isfinite,ys) || continue
            multipliers=Any[[k,string(_fq(-y))] for (k,y) in enumerate(ys) if y<0]
            bound=_flp_margin(d,multipliers;objective_index=d.v[i],objective_sign=sign)
            lo,hi=d.bounds[d.v[i]]
            improvement=sign==1 ? bound-lo : hi+bound
            improvement>_fq(1e-6) || continue
            proof=Dict{String,Any}("index"=>i,"sign"=>sign,"multipliers"=>multipliers,"lower_bound_exact"=>string(bound))
            _flp_apply_bound!(d,proof);push!(bounds,proof)
            lo,hi=d.bounds[d.v[i]]
            set_lower_bound(x[d.v[i]],_flp_round(lo,false));set_upper_bound(x[d.v[i]],_flp_round(hi,true))
        end
        isempty(bounds) && break
        push!(stages,Dict("cuts"=>deepcopy(cuts),"bounds"=>bounds))
        # Each narrower interval has a weak-duality proof. Rebuilding strengthens
        # square envelopes and the full droop convex hull on that proved domain.
        d=_feasibility_lp(p;voltage_bounds=[d.bounds[i] for i in d.v],psd_clique_limit=d.psd_clique_limit)
    end
    attempt=Dict{String,Any}("stage"=>"verified_outer_lp","variables"=>length(d.bounds),
        "rows"=>length(d.rows),"cuts"=>length(cuts),"history"=>history,
        "psd_clique_limit"=>psd_clique_limit,"psd_cliques"=>length(d.cliques),
        "lifted_edges"=>length(d.edges),"psd_cuts"=>count(c->c["kind"]=="psd",cuts),
        "elapsed_seconds"=>time()-start,"time_limit_seconds"=>time_limit,"max_rounds"=>max_rounds,
        "bound_tightening_rounds"=>bound_tightening_rounds,"bound_bus_limit"=>bound_bus_limit,
        "bound_cut_rounds"=>bound_cut_rounds,
        "verified_bound_stages"=>stages,
        "voltage_bounds_pu"=>[[Float64(l),Float64(u)] for (l,u) in d.bounds[d.v]])
    status=isnothing(certificate) ? :unresolved : :certified_infeasible
    r=FeasibilityResult(p.fingerprint,status,nothing,certificate,[attempt],isnothing(certificate) ?
        "sparse outer relaxation was inconclusive" : "exact rational Farkas contradiction of a valid outer relaxation")
    verify_feasibility_result(p,r) || error("internal LP certificate replay failed")
    r
end
