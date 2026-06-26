module AgnosticStorageDynamics

export StorageParams, StorageResult, StoragePhysicalParams, StoragePhysicalResult
export simulate_storage, estimate_physical_profile
export total_spill_energy, total_unmet_energy, total_losses_energy

"""
    StorageParams(; energy_capacity, charge_rate_max, discharge_rate_max,
                    charge_efficiency=1, discharge_efficiency=1,
                    standing_loss_rate=0, energy_min=0)

Container for storage model parameters.

All values are expected in SI units:
- `energy_capacity` and `energy_min` in joules (watt-seconds)
- `charge_rate_max` and `discharge_rate_max` in watts
- `standing_loss_rate` in `s^-1`

The charging and discharging efficiencies are fractional values in `[0, 1]`.
Legacy keyword aliases `charge_power_max` and `discharge_power_max` are
accepted for compatibility.
"""
struct StorageParams{T<:Real}
    energy_capacity::T
    energy_min::T
    charge_rate_max::T
    discharge_rate_max::T
    charge_efficiency::T
    discharge_efficiency::T
    standing_loss_rate::T
end

function StorageParams(;
    energy_capacity::Real,
    charge_rate_max::Union{Nothing,Real} = nothing,
    discharge_rate_max::Union{Nothing,Real} = nothing,
    charge_power_max::Union{Nothing,Real} = nothing,
    discharge_power_max::Union{Nothing,Real} = nothing,
    charge_efficiency::Real = 1,
    discharge_efficiency::Real = 1,
    standing_loss_rate::Real = 0,
    energy_min::Real = 0,
)
    resolved_charge_rate = _resolve_rate_param(
        "charge_rate_max",
        charge_rate_max,
        "charge_power_max",
        charge_power_max,
    )
    resolved_discharge_rate = _resolve_rate_param(
        "discharge_rate_max",
        discharge_rate_max,
        "discharge_power_max",
        discharge_power_max,
    )

    T = promote_type(
        typeof(energy_capacity),
        typeof(energy_min),
        typeof(resolved_charge_rate),
        typeof(resolved_discharge_rate),
        typeof(charge_efficiency),
        typeof(discharge_efficiency),
        typeof(standing_loss_rate),
    )
    params = StorageParams{T}(
        T(energy_capacity),
        T(energy_min),
        T(resolved_charge_rate),
        T(resolved_discharge_rate),
        T(charge_efficiency),
        T(discharge_efficiency),
        T(standing_loss_rate),
    )
    _validate_params(params)
    return params
end

"""
    StorageResult

Result of `simulate_storage`. Arrays have one entry per time step except
`energy`, which has `length(power_in) + 1` entries and includes the initial state.

All powers are in watts and all energies are in joules.
"""
struct StorageResult{T<:Real}
    energy::Vector{T}
    charge_power::Vector{T}
    discharge_power::Vector{T}
    spill_power::Vector{T}
    unmet_demand_power::Vector{T}
    charge_loss_energy::Vector{T}
    discharge_loss_energy::Vector{T}
    standing_loss_energy::Vector{T}
end

"""
    StoragePhysicalParams(; option, baseline_mass=0, baseline_volume=0,
                           specific_energy_density=nothing,
                           volumetric_energy_density=nothing)

Assumptions for converting stored energy (joules) to mass/volume estimates.

Built-in option defaults:
- `option = 1`: battery storage (specific and volumetric energy density defaults)
- `option = 2`: thermal storage (literature-scale sensible/latent storage defaults)
- `option = 3`: desalinated water storage (energy-per-water-production defaults)
- `option = 4`: hydrogen storage (LHV and compressed-gas volumetric defaults)

Units:
- `specific_energy_density` in J/kg
- `volumetric_energy_density` in J/m^3
- `baseline_mass` in kg (empty-system mass)
- `baseline_volume` in m^3 (empty-system volume)
"""
struct StoragePhysicalParams{T<:Real}
    option::Int
    option_name::Symbol
    specific_energy_density::T
    volumetric_energy_density::T
    baseline_mass::T
    baseline_volume::T
end

function StoragePhysicalParams(;
    option::Integer,
    baseline_mass::Real = 0,
    baseline_volume::Real = 0,
    specific_energy_density::Union{Nothing,Real} = nothing,
    volumetric_energy_density::Union{Nothing,Real} = nothing,
)
    defaults = _physical_option_defaults(option)
    resolved_specific_density = specific_energy_density === nothing ? defaults.specific_energy_density : specific_energy_density
    resolved_volumetric_density = volumetric_energy_density === nothing ? defaults.volumetric_energy_density : volumetric_energy_density

    T = promote_type(
        Float64,
        typeof(resolved_specific_density),
        typeof(resolved_volumetric_density),
        typeof(baseline_mass),
        typeof(baseline_volume),
    )
    params = StoragePhysicalParams{T}(
        Int(option),
        defaults.option_name,
        T(resolved_specific_density),
        T(resolved_volumetric_density),
        T(baseline_mass),
        T(baseline_volume),
    )
    _validate_physical_params(params)
    return params
end

"""
    StoragePhysicalResult

Result of `estimate_physical_profile`.

All arrays have one entry per state in the input energy trajectory:
- `stored_mass`: stored medium mass estimate (kg)
- `stored_volume`: stored medium volume estimate (m^3)
- `system_mass`: `baseline_mass + stored_mass` (kg)
- `system_volume`: `baseline_volume + stored_volume` (m^3)
"""
struct StoragePhysicalResult{T<:Real}
    option::Int
    option_name::Symbol
    specific_energy_density::T
    volumetric_energy_density::T
    baseline_mass::T
    baseline_volume::T
    stored_mass::Vector{T}
    stored_volume::Vector{T}
    system_mass::Vector{T}
    system_volume::Vector{T}
end

"""
    simulate_storage(power_in, power_out_demand, params; dt, initial_energy=params.energy_min)

Simulate a generic storage device over a horizon.

The per-step update is:
1. Clamp negative power requests to zero.
2. Accept charging power up to inflow, charge rate, and available capacity.
3. Apply standing losses using an exponential retention factor.
4. Serve discharge demand up to demand, discharge rate, and available energy.

`dt` is the time step in seconds. Inputs and outputs are powers in watts.
"""
function simulate_storage(
    power_in::AbstractVector{<:Real},
    power_out_demand::AbstractVector{<:Real},
    params::StorageParams;
    dt::Real,
    initial_energy::Real = params.energy_min,
)
    n = length(power_in)
    n == length(power_out_demand) || throw(ArgumentError("power vectors must have matching length"))

    T = promote_type(
        eltype(power_in),
        eltype(power_out_demand),
        typeof(dt),
        typeof(initial_energy),
        typeof(params.energy_capacity),
    )
    Δt = T(dt)
    Δt > zero(T) || throw(ArgumentError("`dt` must be positive"))

    p = _convert_params(params, T)
    _validate_params(p)

    E0 = _clamp(T(initial_energy), p.energy_min, p.energy_capacity)
    retention = exp(-p.standing_loss_rate * Δt)

    energy = Vector{T}(undef, n + 1)
    charge_power = zeros(T, n)
    discharge_power = zeros(T, n)
    spill_power = zeros(T, n)
    unmet_demand_power = zeros(T, n)
    charge_loss_energy = zeros(T, n)
    discharge_loss_energy = zeros(T, n)
    standing_loss_energy = zeros(T, n)
    energy[1] = E0

    for k in 1:n
        E_prev = energy[k]
        p_in_k = _positive(T(power_in[k]))
        p_out_k = _positive(T(power_out_demand[k]))

        p_charge = min(p_in_k, p.charge_rate_max)
        room_energy = _positive(p.energy_capacity - E_prev)
        if p.charge_efficiency > zero(T)
            p_charge = min(p_charge, room_energy / (p.charge_efficiency * Δt))
        else
            p_charge = zero(T)
        end

        stored_from_charge = p_charge * Δt * p.charge_efficiency
        charge_loss_energy[k] = p_charge * Δt - stored_from_charge
        spill_power[k] = _positive(p_in_k - p_charge)

        E_post_charge = E_prev + stored_from_charge
        E_after_standing = p.energy_min + (E_post_charge - p.energy_min) * retention
        standing_loss_energy[k] = E_post_charge - E_after_standing

        p_discharge_limit = min(p_out_k, p.discharge_rate_max)
        if p.discharge_efficiency > zero(T)
            p_discharge_limit = min(
                p_discharge_limit,
                _positive(E_after_standing - p.energy_min) * p.discharge_efficiency / Δt,
            )
        else
            p_discharge_limit = zero(T)
        end
        p_discharge = _positive(p_discharge_limit)
        energy_removed = p.discharge_efficiency > zero(T) ? p_discharge * Δt / p.discharge_efficiency : zero(T)

        charge_power[k] = p_charge
        discharge_power[k] = p_discharge
        unmet_demand_power[k] = _positive(p_out_k - p_discharge)
        discharge_loss_energy[k] = energy_removed - p_discharge * Δt
        energy[k + 1] = _clamp(E_after_standing - energy_removed, p.energy_min, p.energy_capacity)
    end

    return StorageResult(
        energy,
        charge_power,
        discharge_power,
        spill_power,
        unmet_demand_power,
        charge_loss_energy,
        discharge_loss_energy,
        standing_loss_energy,
    )
end

"""
    estimate_physical_profile(energy, physical_params)
    estimate_physical_profile(result, physical_params)
    estimate_physical_profile(energy; option, ...)
    estimate_physical_profile(result; option, ...)

Convert an energy trajectory (joules) to estimated stored medium mass/volume and
system mass/volume trajectories.

Passing a `StorageResult` uses `result.energy` directly, so outputs are
time-resolved and aligned with the storage state trajectory.
"""
function estimate_physical_profile(
    energy::AbstractVector{<:Real},
    physical_params::StoragePhysicalParams,
)
    n = length(energy)
    T = promote_type(
        Float64,
        eltype(energy),
        typeof(physical_params.specific_energy_density),
        typeof(physical_params.volumetric_energy_density),
        typeof(physical_params.baseline_mass),
        typeof(physical_params.baseline_volume),
    )
    params = _convert_physical_params(physical_params, T)
    _validate_physical_params(params)

    stored_mass = zeros(T, n)
    stored_volume = zeros(T, n)
    system_mass = zeros(T, n)
    system_volume = zeros(T, n)

    for k in eachindex(energy)
        E = T(energy[k])
        isfinite(E) || throw(ArgumentError("`energy[$k]` must be finite"))
        E >= zero(T) || throw(ArgumentError("`energy[$k]` must be non-negative"))

        stored_mass[k] = E / params.specific_energy_density
        stored_volume[k] = E / params.volumetric_energy_density
        system_mass[k] = params.baseline_mass + stored_mass[k]
        system_volume[k] = params.baseline_volume + stored_volume[k]
    end

    return StoragePhysicalResult(
        params.option,
        params.option_name,
        params.specific_energy_density,
        params.volumetric_energy_density,
        params.baseline_mass,
        params.baseline_volume,
        stored_mass,
        stored_volume,
        system_mass,
        system_volume,
    )
end

estimate_physical_profile(result::StorageResult, physical_params::StoragePhysicalParams) =
    estimate_physical_profile(result.energy, physical_params)

function estimate_physical_profile(
    energy::AbstractVector{<:Real};
    option::Integer,
    baseline_mass::Real = 0,
    baseline_volume::Real = 0,
    specific_energy_density::Union{Nothing,Real} = nothing,
    volumetric_energy_density::Union{Nothing,Real} = nothing,
)
    params = StoragePhysicalParams(
        option = option,
        baseline_mass = baseline_mass,
        baseline_volume = baseline_volume,
        specific_energy_density = specific_energy_density,
        volumetric_energy_density = volumetric_energy_density,
    )
    return estimate_physical_profile(energy, params)
end

estimate_physical_profile(result::StorageResult; kwargs...) =
    estimate_physical_profile(result.energy; kwargs...)

"""
    total_spill_energy(result, dt)

Total spilled input energy over the horizon (joules).
"""
function total_spill_energy(result::StorageResult{T}, dt::Real) where {T<:Real}
    Δt = T(dt)
    return sum(result.spill_power) * Δt
end

"""
    total_unmet_energy(result, dt)

Total unmet discharge demand over the horizon (joules).
"""
function total_unmet_energy(result::StorageResult{T}, dt::Real) where {T<:Real}
    Δt = T(dt)
    return sum(result.unmet_demand_power) * Δt
end

"""
    total_losses_energy(result)

Total storage losses (charge + standing + discharge) over the horizon (joules).
"""
function total_losses_energy(result::StorageResult)
    return sum(result.charge_loss_energy) + sum(result.standing_loss_energy) + sum(result.discharge_loss_energy)
end

function _convert_params(params::StorageParams, ::Type{T}) where {T<:Real}
    return StorageParams{T}(
        T(params.energy_capacity),
        T(params.energy_min),
        T(params.charge_rate_max),
        T(params.discharge_rate_max),
        T(params.charge_efficiency),
        T(params.discharge_efficiency),
        T(params.standing_loss_rate),
    )
end

function _convert_physical_params(params::StoragePhysicalParams, ::Type{T}) where {T<:Real}
    return StoragePhysicalParams{T}(
        params.option,
        params.option_name,
        T(params.specific_energy_density),
        T(params.volumetric_energy_density),
        T(params.baseline_mass),
        T(params.baseline_volume),
    )
end

function _validate_params(p::StorageParams)
    _assert_finite("energy_capacity", p.energy_capacity)
    _assert_finite("energy_min", p.energy_min)
    _assert_finite("charge_rate_max", p.charge_rate_max)
    _assert_finite("discharge_rate_max", p.discharge_rate_max)
    _assert_finite("charge_efficiency", p.charge_efficiency)
    _assert_finite("discharge_efficiency", p.discharge_efficiency)
    _assert_finite("standing_loss_rate", p.standing_loss_rate)

    p.energy_capacity >= zero(p.energy_capacity) || throw(ArgumentError("`energy_capacity` must be non-negative"))
    p.energy_min >= zero(p.energy_min) || throw(ArgumentError("`energy_min` must be non-negative"))
    p.energy_capacity >= p.energy_min || throw(ArgumentError("`energy_capacity` must be >= `energy_min`"))
    p.charge_rate_max >= zero(p.charge_rate_max) || throw(ArgumentError("`charge_rate_max` must be non-negative"))
    p.discharge_rate_max >= zero(p.discharge_rate_max) || throw(ArgumentError("`discharge_rate_max` must be non-negative"))
    _in_unit_interval(p.charge_efficiency) || throw(ArgumentError("`charge_efficiency` must be in [0, 1]"))
    _in_unit_interval(p.discharge_efficiency) || throw(ArgumentError("`discharge_efficiency` must be in [0, 1]"))
    p.standing_loss_rate >= zero(p.standing_loss_rate) || throw(ArgumentError("`standing_loss_rate` must be non-negative"))
    return nothing
end

function _validate_physical_params(p::StoragePhysicalParams)
    _assert_finite("specific_energy_density", p.specific_energy_density)
    _assert_finite("volumetric_energy_density", p.volumetric_energy_density)
    _assert_finite("baseline_mass", p.baseline_mass)
    _assert_finite("baseline_volume", p.baseline_volume)

    p.specific_energy_density > zero(p.specific_energy_density) ||
        throw(ArgumentError("`specific_energy_density` must be positive"))
    p.volumetric_energy_density > zero(p.volumetric_energy_density) ||
        throw(ArgumentError("`volumetric_energy_density` must be positive"))
    p.baseline_mass >= zero(p.baseline_mass) ||
        throw(ArgumentError("`baseline_mass` must be non-negative"))
    p.baseline_volume >= zero(p.baseline_volume) ||
        throw(ArgumentError("`baseline_volume` must be non-negative"))
    return nothing
end

_positive(x::T) where {T<:Real} = x > zero(T) ? x : zero(T)
_clamp(x::T, lo::T, hi::T) where {T<:Real} = min(max(x, lo), hi)
_in_unit_interval(x::T) where {T<:Real} = zero(T) <= x <= one(T)

function _assert_finite(name::String, value::Real)
    isfinite(value) || throw(ArgumentError("`$name` must be finite"))
    return nothing
end

function _resolve_rate_param(
    new_name::String,
    new_value::Union{Nothing,Real},
    legacy_name::String,
    legacy_value::Union{Nothing,Real},
)
    if new_value === nothing && legacy_value === nothing
        throw(ArgumentError("must provide `$new_name`"))
    end
    if new_value !== nothing && legacy_value !== nothing
        throw(ArgumentError("provide only one of `$new_name` or `$legacy_name`"))
    end
    return new_value === nothing ? legacy_value : new_value
end

function _physical_option_defaults(option::Integer)
    if option == 1
        return (
            option_name = :battery,
            specific_energy_density = 6.5e5, # J/kg (about 180 Wh/kg)
            volumetric_energy_density = 1.1e9, # J/m^3 (about 305 Wh/L)
        )
    elseif option == 2
        return (
            option_name = :thermal_storage,
            specific_energy_density = 3.0e5, # J/kg
            volumetric_energy_density = 4.5e8, # J/m^3
        )
    elseif option == 3
        return (
            option_name = :desalinated_water_storage,
            specific_energy_density = 1.26e4, # J/kg (about 3.5 kWh per m^3 with rho=1000 kg/m^3)
            volumetric_energy_density = 1.26e7, # J/m^3
        )
    elseif option == 4
        return (
            option_name = :h2_storage,
            specific_energy_density = 1.2e8, # J/kg (LHV basis)
            volumetric_energy_density = 2.8e9, # J/m^3 (representative compressed H2)
        )
    else
        throw(
            ArgumentError(
                "`option` must be 1 (battery), 2 (thermal storage), 3 (desalinated water storage), or 4 (h2 storage)",
            ),
        )
    end
end

end
