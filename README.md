# AgnosticStorageDynamics.jl

[![CI](https://github.com/sandialabs/AgnosticStorageDynamics.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/sandialabs/AgnosticStorageDynamics.jl/actions/workflows/CI.yml)
[![Docs](https://github.com/sandialabs/AgnosticStorageDynamics.jl/actions/workflows/Docs.yml/badge.svg?branch=master)](https://github.com/sandialabs/AgnosticStorageDynamics.jl/actions/workflows/Docs.yml)

`AgnosticStorageDynamics.jl` is a differentiable, type-stable Julia package for
technology-agnostic storage dynamics simulation with:

- charge/discharge power limits
- charge/discharge efficiencies
- standing losses in storage
- explicit spill and unmet-demand outputs

Inputs and outputs are powers in watts. Internal state is energy in joules
(watt-seconds) over a discrete horizon.

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/sandialabs/AgnosticStorageDynamics.jl")
```

## Quick Usage

```julia
using AgnosticStorageDynamics

params = StorageParams(
    energy_capacity = 400.0,
    charge_rate_max = 100.0,
    discharge_rate_max = 120.0,
    charge_efficiency = 0.95,
    discharge_efficiency = 0.9,
    standing_loss_rate = 0.03,
)

power_in = [250.0, 250.0, 0.0, 0.0]
power_out_demand = [0.0, 0.0, 240.0, 240.0]

result = simulate_storage(power_in, power_out_demand, params; dt = 1.0, initial_energy = 0.0)
physical = estimate_physical_profile(result; option = 1, baseline_mass = 2_000.0, baseline_volume = 2.5)
```

Key outputs:

- `result.energy`
- `result.spill_power`
- `result.unmet_demand_power`
- `result.charge_loss_energy`
- `result.standing_loss_energy`
- `result.discharge_loss_energy`
- `physical.system_mass` and `physical.system_volume` (time-resolved physical estimates)

## Test Coverage Highlights

The default tests include:

- filling to capacity and spilling energy
- idling with standing losses
- pulling down to empty with unmet demand
- random dynamic charge/discharge profiles
- `ForwardDiff` gradient compatibility checks
- optional plotting path (toggle `ENABLE_PLOTTING_TESTS` in `test/runtests.jl`)

## Documentation

Build docs locally:

```julia
julia --project=docs docs/make.jl
```

The docs include quickstart, usage, examples, API autodocs, and a theory page
with a short literature and open-source landscape review.

## License

MIT. See `LICENSE`.
