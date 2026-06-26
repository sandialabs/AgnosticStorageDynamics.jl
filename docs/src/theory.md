# Theory

## Discrete-Time Storage Model

At each time step `k` (step size `dt` in seconds), the model updates stored energy
`E` (joules) from charging, standing losses, and discharging:

\[
P^{\text{ch}}_k = \min\left(P^{\text{in}}_k,\ P^{\text{ch,max}},\ \frac{E^{\max}-E_k}{\eta_{\text{ch}}\,dt}\right)
\]

\[
E^{+}_k = E_k + \eta_{\text{ch}} P^{\text{ch}}_k dt
\]

\[
E^{\text{stand}}_k = E^{\min} + \left(E^{+}_k - E^{\min}\right)e^{-\lambda dt}
\]

\[
P^{\text{dis}}_k = \min\left(P^{\text{dem}}_k,\ P^{\text{dis,max}},\ \frac{(E^{\text{stand}}_k-E^{\min})\eta_{\text{dis}}}{dt}\right)
\]

\[
E_{k+1} = E^{\text{stand}}_k - \frac{P^{\text{dis}}_k dt}{\eta_{\text{dis}}}
\]

Where:

- `ηch` and `ηdis` are charging/discharging efficiencies
- `λ` is the standing loss rate (`s^-1`)
- `Pin` is available charging power and `Pdem` is requested discharge power

Derived outputs:

- spill power: `Pin - Pch` when positive
- unmet demand power: `Pdem - Pdis` when positive
- charge, standing, and discharge losses (joules)

## Physical Estimate Mapping

Optional physical estimates map stored energy `E_k` to mass and volume:

\[
m^{\text{stored}}_k = \frac{E_k}{\rho_E^{m}}, \quad
V^{\text{stored}}_k = \frac{E_k}{\rho_E^{V}}
\]
\[
m^{\text{system}}_k = m^{\text{base}} + m^{\text{stored}}_k, \quad
V^{\text{system}}_k = V^{\text{base}} + V^{\text{stored}}_k
\]

Where `ρE^m` is specific energy density (J/kg) and `ρE^V` is volumetric energy
density (J/m^3).

Built-in option defaults:

- option `1` battery: `ρE^m = 6.5e5`, `ρE^V = 1.1e9`
- option `2` thermal storage: `ρE^m = 3.0e5`, `ρE^V = 4.5e8`
- option `3` desalinated water storage: `ρE^m = 1.26e4`, `ρE^V = 1.26e7`
- option `4` h2 storage: `ρE^m = 1.2e8`, `ρE^V = 2.8e9`

## Differentiability Notes

The implementation is type-stable and AD-compatible with `ForwardDiff`.
Dynamics are piecewise smooth because physical constraints use `min/max/clamp`.
Gradients are well-defined away from active-set switching boundaries, which is
the standard behavior for constrained energy system models.

## Literature Snapshot

Battery modeling references used to shape assumptions:

- Navas et al. (2023), dynamic Li-ion equivalent-circuit model for renewable applications: https://doi.org/10.1016/j.egyr.2023.03.103
- Kampker et al. (2025), modular BESS modeling integrating electrical, thermal, and aging effects: https://doi.org/10.3390/batteries11110392
- Babu (2024), review of self-discharge mechanisms and models across rechargeable storage technologies: https://doi.org/10.1016/j.ensm.2024.103261

Thermal storage reference used for cross-technology framing:

- Mao et al. (2025), thermal energy storage review for phase-change materials and standing-loss-relevant behavior: https://doi.org/10.1016/j.enss.2025.03.001

## Open-Source Landscape Review

Close existing formulations:

- PyPSA `StorageUnit` state transition and standing-loss terms: https://docs.pypsa.org/latest/user-guide/optimization/storage/
- oemof.solph `GenericStorage` balance equations with inflow/outflow conversion factors and loss rate: https://oemof-solph.readthedocs.io/en/latest/reference/oemof.solph.components.html#module-oemof.solph.components._generic_storage
- Calliope `balance_storage` equations with storage loss and timestep scaling: https://calliope.readthedocs.io/en/latest/math/built_in/storage_inter_cluster/
- GenX storage constraints for charging/discharging and state-of-charge linkage: https://genxproject.github.io/GenX.jl/stable/Model_Reference/Resources/storage/
- PowerSystems.jl includes `EnergyReservoirStorage` data structures (component-level representation): https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/generated_EnergyReservoirStorage/
- BattMo offers detailed battery electrochemistry models with AD support, but it is battery-specific rather than generic storage dispatch abstraction: https://battmoteam.github.io/BattMo/

Conclusion as of 2026-02-12:

- no widely used Julia package was found that exactly matches this package's
  specific target: a lightweight, generic, differentiable forward simulator for
  power-in/power-out storage dynamics with explicit spill and unmet-demand
  outputs across storage technologies.

## SIRENOpt Integration Boundary

SIRENOpt uses this package as a generic reservoir abstraction for batteries,
hydrogen buffers, thermal storage, and potable-water storage. The stable exchange
variables are available charge power, demanded discharge power, stored energy,
spill, unmet demand, mass, and volume. Technology-specific packages can replace
this abstraction when they preserve those quantities at the subsystem boundary.
