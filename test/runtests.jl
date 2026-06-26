using FiniteDiff
using ForwardDiff
using AgnosticStorageDynamics
using Random
using Test

@testset "Fill and spill dynamics" begin
    params = StorageParams(
        energy_capacity = 10.0,
        charge_rate_max = 4.0,
        discharge_rate_max = 10.0,
        charge_efficiency = 1.0,
        discharge_efficiency = 1.0,
        standing_loss_rate = 0.0,
    )

    power_in = [10.0, 10.0, 10.0]
    power_out = zeros(3)
    result = simulate_storage(power_in, power_out, params; dt = 1.0, initial_energy = 0.0)

    @test result.energy == [0.0, 4.0, 8.0, 10.0]
    @test result.charge_power == [4.0, 4.0, 2.0]
    @test result.spill_power == [6.0, 6.0, 8.0]
    @test total_spill_energy(result, 1.0) == 20.0
end

@testset "Standing losses while idle" begin
    params = StorageParams(
        energy_capacity = 200.0,
        energy_min = 0.0,
        charge_rate_max = 0.0,
        discharge_rate_max = 0.0,
        charge_efficiency = 1.0,
        discharge_efficiency = 1.0,
        standing_loss_rate = log(2.0),
    )

    result = simulate_storage(zeros(3), zeros(3), params; dt = 1.0, initial_energy = 100.0)
    @test result.energy ≈ [100.0, 50.0, 25.0, 12.5] atol = 1e-12
    @test result.standing_loss_energy ≈ [50.0, 25.0, 12.5] atol = 1e-12
end

@testset "Depletion and unmet demand" begin
    params = StorageParams(
        energy_capacity = 50.0,
        charge_rate_max = 50.0,
        discharge_rate_max = 50.0,
        charge_efficiency = 1.0,
        discharge_efficiency = 1.0,
        standing_loss_rate = 0.0,
    )

    result = simulate_storage([0.0], [8.0], params; dt = 1.0, initial_energy = 5.0)
    @test result.discharge_power == [5.0]
    @test result.unmet_demand_power == [3.0]
    @test result.energy[end] == 0.0
end

@testset "Integrated scenario with random tail" begin
    Random.seed!(7)
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

    power_in = vcat(
        fill(250.0, fill_steps), # fill and spill
        zeros(idle_steps), # sit and lose
        zeros(pull_steps), # pull to empty
        150.0 .* rand(random_steps), # random tail
        zeros(prep_empty_steps), # drain before charge-rate checks
        fill(80.0, charge_within_steps), # below charge rate limit
        fill(160.0, charge_exceed_steps), # above charge rate limit
        fill(250.0, prep_discharge_steps), # refill before discharge-rate checks
        zeros(discharge_within_steps), # below discharge rate limit
        zeros(discharge_exceed_steps), # above discharge rate limit
    )
    power_out = vcat(
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
    result = simulate_storage(power_in, power_out, params; dt = dt, initial_energy = 0.0)

    @test length(result.energy) == length(power_in) + 1
    @test maximum(result.spill_power[fill_range]) > 0.0
    @test all(result.standing_loss_energy[idle_range] .> 0.0)
    @test sum(result.unmet_demand_power[pull_range]) > 0.0
    @test minimum(result.energy) >= params.energy_min - 1e-10
    @test maximum(result.energy) <= params.energy_capacity + 1e-10
    @test total_unmet_energy(result, dt) > 0
    @test total_losses_energy(result) > 0
    @test total_steps == length(power_in) == length(power_out)
    @test all(result.charge_power .<= params.charge_rate_max .+ 1e-10)
    @test all(result.discharge_power .<= params.discharge_rate_max .+ 1e-10)
    @test all(power_in[charge_exceed_range] .> params.charge_rate_max)
    @test all(power_out[discharge_exceed_range] .> params.discharge_rate_max)

    # In-window checks for sub-limit and super-limit rate requests.
    @test all(isapprox.(result.charge_power[charge_within_range], power_in[charge_within_range]; atol = 1e-10))
    @test all(result.charge_power[charge_exceed_range] .<= params.charge_rate_max .+ 1e-10)
    @test all(isapprox.(result.charge_power[charge_exceed_range], params.charge_rate_max; atol = 1e-10))
    @test all(isapprox.(result.discharge_power[discharge_within_range], power_out[discharge_within_range]; atol = 1e-10))
    @test all(result.discharge_power[discharge_exceed_range] .<= params.discharge_rate_max .+ 1e-10)
    @test any(isapprox.(result.discharge_power[discharge_exceed_range], params.discharge_rate_max; atol = 1e-10))

    for k in eachindex(power_in)
        energy_removed = params.discharge_efficiency > 0 ? result.discharge_power[k] * dt / params.discharge_efficiency : 0.0
        expected_next = result.energy[k] +
                        result.charge_power[k] * dt * params.charge_efficiency -
                        result.standing_loss_energy[k] -
                        energy_removed
        @test isapprox(
            result.energy[k + 1],
            clamp(expected_next, params.energy_min, params.energy_capacity);
            atol = 1e-10,
        )
    end

end

@testset "Type handling and AD" begin
    params32 = StorageParams(
        energy_capacity = 100f0,
        charge_rate_max = 50f0,
        discharge_rate_max = 50f0,
        charge_efficiency = 0.95f0,
        discharge_efficiency = 0.95f0,
        standing_loss_rate = 0.01f0,
    )
    result32 = simulate_storage(Float32[10, 10, 0], Float32[0, 0, 5], params32; dt = 1f0, initial_energy = 0f0)
    @test eltype(result32.energy) == Float32
    @test eltype(result32.charge_power) == Float32

    pin = fill(20.0, 8)
    pout = fill(18.0, 8)
    dt = 1.0

    σ(x) = inv(one(x) + exp(-x))
    softplus(x) = log1p(exp(x))

    function objective(θ)
        ηc = 0.2 + 0.79 * σ(θ[1])
        ηd = 0.2 + 0.79 * σ(θ[2])
        λ = 0.001 + 0.02 * softplus(θ[3])
        p = StorageParams(
            energy_capacity = 1_000.0,
            charge_rate_max = 1_000.0,
            discharge_rate_max = 1_000.0,
            charge_efficiency = ηc,
            discharge_efficiency = ηd,
            standing_loss_rate = λ,
        )
        result = simulate_storage(pin, pout, p; dt = dt, initial_energy = 300.0)
        return total_unmet_energy(result, dt) + 1e-3 * total_losses_energy(result)
    end

    θ0 = [0.3, 0.7, -2.0]
    g_ad = ForwardDiff.gradient(objective, θ0)
    g_fd = FiniteDiff.finite_difference_gradient(objective, θ0, Val(:central))
    @test all(isfinite.(g_ad))
    @test all(isfinite.(g_fd))
    @test all(isapprox.(g_ad, g_fd; rtol = 1e-6, atol = 1e-8))
end

@testset "Physical profile estimates" begin
    energy = [0.0, 2.0e6, 5.0e6]
    desal_profile = estimate_physical_profile(
        energy;
        option = 3,
        baseline_mass = 1_000.0,
        baseline_volume = 8.0,
    )

    @test desal_profile.option == 3
    @test desal_profile.option_name == :desalinated_water_storage
    @test length(desal_profile.stored_mass) == length(energy)
    @test length(desal_profile.system_mass) == length(energy)
    @test desal_profile.system_mass[1] == 1_000.0
    @test desal_profile.system_volume[1] == 8.0
    @test desal_profile.system_mass[end] > desal_profile.system_mass[1]
    @test desal_profile.system_volume[end] > desal_profile.system_volume[1]
    @test all(isapprox.(desal_profile.system_mass, desal_profile.baseline_mass .+ desal_profile.stored_mass; atol = 1e-12))
    @test all(isapprox.(desal_profile.system_volume, desal_profile.baseline_volume .+ desal_profile.stored_volume; atol = 1e-12))

    params = StorageParams(
        energy_capacity = 10.0,
        charge_rate_max = 10.0,
        discharge_rate_max = 10.0,
    )
    result = simulate_storage([10.0, 0.0], [0.0, 0.0], params; dt = 1.0, initial_energy = 0.0)
    battery_profile = estimate_physical_profile(result; option = 1, baseline_mass = 50.0)
    @test length(battery_profile.system_mass) == length(result.energy)
    @test battery_profile.option_name == :battery

    thermal_params = StoragePhysicalParams(option = 2, baseline_mass = 200.0)
    thermal_profile = estimate_physical_profile(energy, thermal_params)
    @test thermal_profile.option == 2
    @test thermal_profile.option_name == :thermal_storage
    @test thermal_profile.system_mass[end] > thermal_profile.system_mass[1]

    @test_throws ArgumentError StoragePhysicalParams(option = 5)
    @test_throws ArgumentError StoragePhysicalParams(option = 1, baseline_mass = -1.0)
    @test_throws ArgumentError StoragePhysicalParams(option = 1, specific_energy_density = 0.0)
    @test_throws ArgumentError estimate_physical_profile([-1.0, 0.0]; option = 1)
end

@testset "Fringe cases and validation" begin
    @test_throws ArgumentError StorageParams(
        energy_capacity = 1.0,
        charge_rate_max = 1.0,
        discharge_rate_max = 1.0,
        charge_efficiency = 1.1,
    )

    params = StorageParams(
        energy_capacity = 10.0,
        charge_rate_max = 10.0,
        discharge_rate_max = 10.0,
        charge_efficiency = 0.0,
        discharge_efficiency = 0.0,
        standing_loss_rate = 0.0,
    )
    result = simulate_storage([-5.0, 5.0], [-2.0, 5.0], params; dt = 1.0, initial_energy = 5.0)
    @test result.charge_power == [0.0, 0.0]
    @test result.discharge_power == [0.0, 0.0]
    @test result.energy == [5.0, 5.0, 5.0]
    @test result.unmet_demand_power == [0.0, 5.0]
    @test result.spill_power == [0.0, 5.0]

    stable_params = StorageParams(
        energy_capacity = 10.0,
        charge_rate_max = 5.0,
        discharge_rate_max = 5.0,
    )
    @test_throws ArgumentError simulate_storage([1.0], [1.0, 2.0], stable_params; dt = 1.0)
    @test_throws ArgumentError simulate_storage([1.0], [1.0], stable_params; dt = 0.0)

    legacy_params = StorageParams(
        energy_capacity = 10.0,
        charge_power_max = 3.0,
        discharge_power_max = 4.0,
    )
    @test legacy_params.charge_rate_max == 3.0
    @test legacy_params.discharge_rate_max == 4.0
    @test_throws ArgumentError StorageParams(
        energy_capacity = 10.0,
        charge_rate_max = 3.0,
        charge_power_max = 3.0,
        discharge_rate_max = 4.0,
    )
end
