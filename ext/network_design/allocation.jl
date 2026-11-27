function bounded_share(total,weights,lower,upper;tol=1e-9)
    n=length(weights)
    require_network(n>0&&length(lower)==n&&length(upper)==n,"Invalid allocation dimensions")
    require_network(all(isfinite,weights)&&all(>=(0),weights)&&all(lower .<= upper),"Invalid allocation data")
    total>=sum(lower)-tol&&total<=sum(upper)+tol||error("Plant Q is outside aggregate machine capability")
    total=clamp(total,sum(lower),sum(upper))
    # Zero-weight machines hold the closest feasible value to zero until the
    # positive-P machines exhaust their capability; then use the stated fallback.
    fixed=findall(iszero,weights);live=findall(>(0),weights);out=clamp.(zeros(n),lower,upper)
    if isempty(live);live=collect(1:n);fixed=Int[];weights=ones(n);end
    target=total-sum(out[i] for i in fixed;init=0.)
    if target<sum(lower[live])-tol||target>sum(upper[live])+tol
        # Zero-P units can supply residual Q once nonzero-P units reach limits.
        out[live].=target<sum(lower[live]) ? lower[live] : upper[live]
        out[fixed]=bounded_share(total-sum(out[live]),ones(length(fixed)),lower[fixed],upper[fixed];tol)
        return out
    end
    # Monotone clipped proportional allocation, valid for positive AND negative Q.
    lo=minimum(lower[i]/weights[i] for i in live)-1
    hi=maximum(upper[i]/weights[i] for i in live)+1
    for _ in 1:100
        mid=(lo+hi)/2
        sum(clamp(weights[i]*mid,lower[i],upper[i]) for i in live)<target ? (lo=mid) : (hi=mid)
    end
    for i in live;out[i]=clamp(weights[i]*(lo+hi)/2,lower[i],upper[i]);end
    abs(sum(out)-total)<=max(tol,1e-10*abs(total))||error("Machine allocation residual")
    out
end
