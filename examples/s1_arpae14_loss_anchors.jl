include("s1_arpae14_demand_anchors.jl")
demand_anchor_matrix(;out=joinpath(GATED_ROOT,"artifacts/s1_arpae14_loss_anchors"),start_label="loss_anchor",seed_objective="total active power losses")
