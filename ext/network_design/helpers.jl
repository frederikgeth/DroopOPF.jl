function static_fields(data)
    out=deepcopy(data)
    for (table,fields) in (("bus",("vm","va")),("gen",("pg","qg")),("branch",("pf","pt","qf","qt")))
        for row in values(get(out,table,Dict())),field in fields;pop!(row,field,nothing);end
    end
    out
end
livegen(g)=get(g,"gen_status",0)!=0
boundary(g)=startswith(get(g,"name",""),"interconnector_")
require_network(condition,message)=condition||error(message)
regulation_plan(x,controls)=x.regulation
equipment_plan(x)=x.equipment
