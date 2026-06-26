# # Dynamic Profile With Rate-Limit Windows
#
# This scenario mirrors the integration test and exercises:
# 1. fill to capacity and spill
# 2. idle standing losses
# 3. pull-down to empty with unmet demand
# 4. random dynamic input/output
# 5. appended charge/discharge windows below and above configured rate limits
# 6. optional annotated plotting of each period

using AgnosticStorageDynamics
using Random

Random.seed!(7)

# Define scenario windows.
fill_steps = 6
idle_steps = 5
pull_steps = 5
random_steps = 30
prep_empty_steps = 10
charge_within_steps = 2
charge_exceed_steps = 2
prep_discharge_steps = 4
discharge_within_steps = 2
discharge_exceed_steps = 2

# Build contiguous index ranges so plots and checks can be window-aware.
cursor = 1
fill_range = cursor:(cursor + fill_steps - 1)
cursor += fill_steps
idle_range = cursor:(cursor + idle_steps - 1)
cursor += idle_steps
pull_range = cursor:(cursor + pull_steps - 1)
cursor += pull_steps
random_range = cursor:(cursor + random_steps - 1)
cursor += random_steps
prep_empty_range = cursor:(cursor + prep_empty_steps - 1)
cursor += prep_empty_steps
charge_within_range = cursor:(cursor + charge_within_steps - 1)
cursor += charge_within_steps
charge_exceed_range = cursor:(cursor + charge_exceed_steps - 1)
cursor += charge_exceed_steps
prep_discharge_range = cursor:(cursor + prep_discharge_steps - 1)
cursor += prep_discharge_steps
discharge_within_range = cursor:(cursor + discharge_within_steps - 1)
cursor += discharge_within_steps
discharge_exceed_range = cursor:(cursor + discharge_exceed_steps - 1)
cursor += discharge_exceed_steps
total_steps = cursor - 1

# Build input and demand power profiles in watts.
power_in = vcat(
    fill(250.0, fill_steps),
    zeros(idle_steps),
    zeros(pull_steps),
    150.0 .* rand(random_steps),
    zeros(prep_empty_steps),
    fill(80.0, charge_within_steps),
    fill(160.0, charge_exceed_steps),
    fill(250.0, prep_discharge_steps),
    zeros(discharge_within_steps),
    zeros(discharge_exceed_steps),
)

power_out_demand = vcat(
    zeros(fill_steps),
    zeros(idle_steps),
    fill(240.0, pull_steps),
    120.0 .* rand(random_steps),
    fill(240.0, prep_empty_steps),
    zeros(charge_within_steps),
    zeros(charge_exceed_steps),
    zeros(prep_discharge_steps),
    fill(90.0, discharge_within_steps),
    fill(200.0, discharge_exceed_steps),
)

params = StorageParams(
    energy_capacity = 500.0,
    charge_rate_max = 100.0,
    discharge_rate_max = 120.0,
    charge_efficiency = 0.95,
    discharge_efficiency = 0.9,
    standing_loss_rate = 0.03,
)

dt = 1.0
result = simulate_storage(power_in, power_out_demand, params; dt = dt, initial_energy = 0.0)

# Physical estimate profiles for options:
# 1 battery, 2 thermal storage, 3 desalinated water storage, 4 h2 storage.
physical_profiles = Dict(
    1 => estimate_physical_profile(
        result;
        option = 1,
        baseline_mass = 2_000.0,
        baseline_volume = 2.5,
    ),
    2 => estimate_physical_profile(
        result;
        option = 2,
        baseline_mass = 4_500.0,
        baseline_volume = 6.0,
    ),
    3 => estimate_physical_profile(
        result;
        option = 3,
        baseline_mass = 8_000.0,
        baseline_volume = 12.0,
    ),
    4 => estimate_physical_profile(
        result;
        option = 4,
        baseline_mass = 1_000.0,
        baseline_volume = 4.0,
    ),
)
desal_profile = physical_profiles[3]

# Basic checks.
@assert total_steps == length(power_in) == length(power_out_demand)
@assert maximum(result.spill_power[fill_range]) > 0.0
@assert all(result.standing_loss_energy[idle_range] .> 0.0)
@assert sum(result.unmet_demand_power[pull_range]) > 0.0
@assert all(result.charge_power .<= params.charge_rate_max .+ 1e-10)
@assert all(result.discharge_power .<= params.discharge_rate_max .+ 1e-10)
@assert all(power_in[charge_exceed_range] .> params.charge_rate_max)
@assert all(power_out_demand[discharge_exceed_range] .> params.discharge_rate_max)
@assert desal_profile.system_mass[1] == desal_profile.baseline_mass
@assert maximum(desal_profile.system_mass) > desal_profile.system_mass[1]

# Rate-limit windows.
@assert all(isapprox.(result.charge_power[charge_within_range], power_in[charge_within_range]; atol = 1e-10))
@assert all(isapprox.(result.charge_power[charge_exceed_range], params.charge_rate_max; atol = 1e-10))
@assert all(isapprox.(result.discharge_power[discharge_within_range], power_out_demand[discharge_within_range]; atol = 1e-10))
@assert any(isapprox.(result.discharge_power[discharge_exceed_range], params.discharge_rate_max; atol = 1e-10))

(
    total_spill_J = total_spill_energy(result, dt),
    total_unmet_J = total_unmet_energy(result, dt),
    total_losses_J = total_losses_energy(result),
    final_system_mass_by_option_kg = Dict(k => v.system_mass[end] for (k, v) in physical_profiles),
    final_system_volume_by_option_m3 = Dict(k => v.system_volume[end] for (k, v) in physical_profiles),
    desalinated_water_mass_range_kg = extrema(desal_profile.system_mass),
)

# The computed trajectories can be plotted interactively after adding `Plots`
# to the active environment:
#
# ```julia
# using Plots
#
# t = 0:length(power_in)
# p = plot(
#     t,
#     result.energy;
#     label = "Stored energy (J)",
#     xlabel = "step",
#     ylabel = "value",
#     legend = (0.5, 0.5),
# )
# plot!(p, 1:length(power_in), result.charge_power; label = "charge power (W)")
# plot!(p, 1:length(power_in), result.discharge_power; label = "discharge power (W)")
# ymax = maximum(result.energy)
# window_specs = [
#     (fill_range, "fill/spill", :lightskyblue),
#     (idle_range, "idle-loss", :lightgreen),
#     (pull_range, "pull-down", :mistyrose),
#     (random_range, "random", :lightgray),
#     (prep_empty_range, "drain-prep", :wheat),
#     (charge_within_range, "charge<=rate", :honeydew),
#     (charge_exceed_range, "charge>rate", :khaki),
#     (prep_discharge_range, "refill-prep", :wheat),
#     (discharge_within_range, "discharge<=rate", :lavender),
#     (discharge_exceed_range, "discharge>rate", :thistle),
# ]
# for (range, label, color) in window_specs
#     vspan!(p, [first(range) - 0.5, last(range) + 0.5]; color = color, alpha = 0.08, label = "")
#     midpoint = (first(range) + last(range)) / 2
#     annotate!(p, midpoint, ymax * 1.08, text(label, 7, :black, rotation = 30))
# end
# ylims!(p, 0, ymax * 1.2)
# display(p)
# ```
