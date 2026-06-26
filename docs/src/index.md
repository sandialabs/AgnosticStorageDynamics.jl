# AgnosticStorageDynamics.jl

`AgnosticStorageDynamics.jl` is a differentiable, type-stable Julia package for
technology-agnostic storage dynamics with:

- charging limits and charging losses
- standing losses while stored
- discharging limits and discharging losses
- explicit spill and unmet-demand accounting
- optional physical mass/volume estimates from the simulated energy trajectory

Inputs are power time series in watts (`power_in`, `power_out_demand`) and
simulation advances over a user-defined time step `dt` in seconds.

## What This Package Is For

- fast forward simulation over arbitrary horizons
- gradient-based workflows (`ForwardDiff`) with piecewise-smooth dynamics
- representing batteries, thermal storage, hydrogen buffers, or other
  reservoir-like storage technologies using one consistent formulation

## Docs Map

- [Quickstart](quickstart.md)
- [Usage](usage.md)
- [Examples](examples.md)
- [Theory and Literature](theory.md)
- [API](api.md)
