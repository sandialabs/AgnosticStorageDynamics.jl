# Usage

## Parameterization

`StorageParams` is technology-agnostic:

```julia
params = StorageParams(
    energy_capacity = 1.0e7,    # J
    energy_min = 0.0,           # J
    charge_rate_max = 5.0e5,    # W
    discharge_rate_max = 4e5,   # W
    charge_efficiency = 0.96,   # fraction
    discharge_efficiency = 0.93,# fraction
    standing_loss_rate = 5e-6,  # 1/s
)
```

Typical mappings:

- battery storage: set efficiencies near 0.9 to 0.98, low standing loss
- thermal storage: set standing loss higher, tune efficiencies to heat exchanger behavior
- hydrogen/chemical storage proxy: set conversion efficiencies and standing loss to reflect subsystem behavior

## Simulation Call

```julia
result = simulate_storage(power_in, power_out_demand, params; dt = 900.0, initial_energy = 1.0e6)
```

Rules:

- negative `power_in` and `power_out_demand` entries are treated as zero
- charging is capped by input availability, `charge_rate_max`, and available room
- standing losses are exponential with `exp(-standing_loss_rate * dt)`
- discharging is capped by demand, `discharge_rate_max`, and available energy

## Aggregates

```julia
total_spill_energy(result, 900.0)
total_unmet_energy(result, 900.0)
total_losses_energy(result)
```

All aggregate energies are in joules.

## Physical Mass/Volume Estimates

Map the simulated energy trajectory to mass/volume with built-in options:

- `option = 1`: battery
- `option = 2`: thermal storage
- `option = 3`: desalinated water storage
- `option = 4`: h2 storage

```julia
physical = estimate_physical_profile(
    result;
    option = 3,
    baseline_mass = 8_000.0,   # kg, empty tank + balance of plant
    baseline_volume = 12.0,    # m^3, empty system volume
)

physical.system_mass    # kg, time-resolved
physical.system_volume  # m^3, time-resolved
```

`physical.system_mass` is the total system mass over time, so a water-tank
representation can start at a baseline mass and increase while filling.
