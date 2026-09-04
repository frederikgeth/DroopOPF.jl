function _bus_indices(network::ACNetwork)
    return Dict(bus.id => i for (i, bus) in enumerate(network.buses))
end

function _admittance_matrix(network::ACNetwork{T}) where {T<:Real}
    n = length(network.buses)
    Y = zeros(Complex{T}, n, n)
    indices = _bus_indices(network)
    for branch in network.branches
        branch.available || continue
        i, j = indices[branch.from_bus], indices[branch.to_bus]
        y = inv(complex(branch.resistance, branch.reactance))
        y_shunt = complex(zero(T), branch.charging / 2)
        Y[i, i] += y + y_shunt
        Y[j, j] += y + y_shunt
        Y[i, j] -= y
        Y[j, i] -= y
    end
    return Y
end

function power_balance(
    network::ACNetwork,
    state::ACState,
    generators::AbstractVector{<:Generator},
    loads::AbstractVector{<:Load},
)
    length(state.vm) == length(network.buses) ||
        throw(ArgumentError("state voltage vectors must follow network bus order"))
    length(state.pg) == length(generators) ||
        throw(ArgumentError("state generator vectors must follow generator order"))
    bus_indices = _bus_indices(network)
    p_inj = zeros(eltype(state.vm), length(network.buses))
    q_inj = zeros(eltype(state.vm), length(network.buses))
    for (i, generator) in enumerate(generators)
        generator.available || continue
        bus = get(bus_indices, generator.bus_id, 0)
        bus > 0 || throw(ArgumentError("generator references an unknown bus"))
        p_inj[bus] += state.pg[i]
        q_inj[bus] += state.qg[i]
    end
    for load in loads
        bus = get(bus_indices, load.bus_id, 0)
        bus > 0 || throw(ArgumentError("load references an unknown bus"))
        p_inj[bus] -= load.p
        q_inj[bus] -= load.q
    end

    voltage = state.vm .* cis.(state.va)
    network_injection = voltage .* conj.(_admittance_matrix(network) * voltage)
    p_residual = p_inj .- real.(network_injection)
    q_residual = q_inj .- imag.(network_injection)
    return (active = p_residual, reactive = q_residual,
            vector = vcat(p_residual, q_residual))
end

function branch_flows(network::ACNetwork, state::ACState)
    length(state.vm) == length(network.buses) ||
        throw(ArgumentError("state voltage vectors must follow network bus order"))
    bus_indices = _bus_indices(network)
    voltage = state.vm .* cis.(state.va)
    from_power = zeros(Complex{eltype(state.vm)}, length(network.branches))
    to_power = similar(from_power)
    for (k, branch) in enumerate(network.branches)
        branch.available || continue
        i, j = bus_indices[branch.from_bus], bus_indices[branch.to_bus]
        y = inv(complex(branch.resistance, branch.reactance))
        y_shunt = complex(zero(eltype(state.vm)), branch.charging / 2)
        current_from = (y + y_shunt) * voltage[i] - y * voltage[j]
        current_to = (y + y_shunt) * voltage[j] - y * voltage[i]
        from_power[k] = voltage[i] * conj(current_from)
        to_power[k] = voltage[j] * conj(current_to)
    end
    return (from = from_power, to = to_power)
end

function operating_margins(network::ACNetwork, state::ACState)
    flows = branch_flows(network, state)
    return [
        branch.available ? branch.thermal_limit - max(abs(flows.from[i]), abs(flows.to[i])) : Inf
        for (i, branch) in enumerate(network.branches)
    ]
end

function power_balance(case::Case, state::ACState)
    isnothing(case.network) && throw(ArgumentError("case has no AC network"))
    return power_balance(case.network, state, case.generators, case.loads)
end

function droop_residual(case::Case, state::ACState)
    isnothing(case.network) && throw(ArgumentError("case has no AC network"))
    bus_indices = _bus_indices(case.network)
    generator_indices = Dict(generator.id => i for (i, generator) in enumerate(case.generators))
    residual = Float64[]
    for attachment in case.attachments
        generator_index = generator_indices[attachment.generator_id]
        generator = case.generators[generator_index]
        generator.available || continue
        control = case.controls[attachment.control_id]
        bus_index = get(bus_indices, attachment.location.bus_id, 0)
        bus_index > 0 || throw(ArgumentError("control location references an unknown bus"))
        expected_q = droop_response(control, state.vm[bus_index]; p = state.pg[generator_index])
        push!(residual, state.qg[generator_index] - expected_q)
    end
    return residual
end

function equilibrium_residual(case::Case, state::ACState)
    balance = power_balance(case, state)
    droop = droop_residual(case, state)
    return (power = balance, droop = droop, vector = vcat(balance.vector, droop))
end
