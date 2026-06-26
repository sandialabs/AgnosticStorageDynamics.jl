# Quickstart

```julia
using AgnosticStorageDynamics

params = StorageParams(
    energy_capacity = 5e6,      # J
    charge_rate_max = 2e5,      # W
    discharge_rate_max = 2e5,   # W
    charge_efficiency = 0.95,
    discharge_efficiency = 0.92,
    standing_loss_rate = 1e-5,  # 1/s
)

power_in = [2e5, 2e5, 0.0, 0.0]          # W
power_out_demand = [0.0, 0.0, 1e5, 1e5]  # W

result = simulate_storage(
    power_in,
    power_out_demand,
    params;
    dt = 3600.0,
    initial_energy = 0.0,
)

result.energy
result.spill_power
result.unmet_demand_power

physical = estimate_physical_profile(result; option = 1, baseline_mass = 2_000.0, baseline_volume = 2.5)
physical.system_mass
```

Key outputs:

- `result.energy`: stored energy trajectory (J), length `N + 1`
- `result.spill_power`: unaccepted charge input (W)
- `result.unmet_demand_power`: unmet output demand (W)
- `result.charge_loss_energy`, `result.standing_loss_energy`, `result.discharge_loss_energy`: per-step losses (J)
- `physical.system_mass`, `physical.system_volume`: optional time-resolved physical estimates
