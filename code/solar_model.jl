using Random
using Plots

include(joinpath(@__DIR__, "color-scheme", "julia", "Fieldline.jl"))
using .Fieldline

"""
Illustrative solar model. Time is in hours and electrical power is in watts.

    P_solar(t) = P_clear(t) X(t)
    dX = κ(μ - X) dt + σ sqrt(X(1-X)) dW

κ has units h⁻¹ and σ has units h⁻¹ᐟ². The clear-sky envelope is an idealized
half-sine between sunrise and sunset, not a calibrated irradiance forecast.
"""
Base.@kwdef struct SolarParameters
    peak_power::Float64 = 250.0
    sunrise::Float64 = 6.0
    sunset::Float64 = 18.0
    κ::Float64 = 2.0
    μ::Float64 = 0.65
    σ::Float64 = 0.60
end

function validate(p::SolarParameters)
    all(isfinite, (p.peak_power, p.sunrise, p.sunset, p.κ, p.μ, p.σ)) ||
        throw(ArgumentError("All parameters must be finite."))
    p.peak_power > 0 || throw(ArgumentError("Peak power must be positive."))
    0 <= p.sunrise < p.sunset <= 24 ||
        throw(ArgumentError("Require 0 ≤ sunrise < sunset ≤ 24 hours."))
    p.κ > 0 && 0 < p.μ < 1 && p.σ >= 0 ||
        throw(ArgumentError("Require κ > 0, 0 < μ < 1, and σ ≥ 0."))
    p.σ^2 <= 2p.κ * min(p.μ, 1 - p.μ) ||
        throw(ArgumentError("Require σ² ≤ 2κ min(μ, 1-μ), as in the proposal."))
    return p
end

"""Idealized clear-sky electrical power, repeated every 24 hours."""
function clear_sky_power(t::Real, p::SolarParameters)
    hour = mod(t, 24)
    if hour <= p.sunrise || hour >= p.sunset
        return 0.0
    end
    return p.peak_power * sinpi((hour - p.sunrise) / (p.sunset - p.sunrise))
end

cloud_drift(x, p::SolarParameters, t=0.0) = p.κ * (p.μ - x)
cloud_diffusion(x, p::SolarParameters, t=0.0) = p.σ * sqrt(x * (1 - x))

# Lamperti transform θ = 2 asin(sqrt(X)) gives constant diffusion σ and drift
# f(θ) = A cot(θ/2) - B tan(θ/2), where
# A = κμ - σ²/4, B = κ(1-μ) - σ²/4.
# Both coefficients are positive under the parameter restriction above.
# Solve θ_next - dt f(θ_next) = θ + σ ΔW by bisection on (0, π).
# The left-hand side is strictly increasing with infinite endpoint limits.
# This is a drift-implicit approximation, not exact transition sampling.
function cloud_step(θ::Float64, dt::Float64, ΔW::Float64, p::SolarParameters)
    A = p.κ * p.μ - p.σ^2 / 4
    B = p.κ * (1 - p.μ) - p.σ^2 / 4
    target = θ + p.σ * ΔW
    lower, upper = 0.0, Float64(π)
    for _ in 1:52
        candidate = (lower + upper) / 2
        drift = A / tan(candidate / 2) - B * tan(candidate / 2)
        if candidate - dt * drift > target
            upper = candidate
        else
            lower = candidate
        end
    end
    return (lower + upper) / 2
end

"""
    simulate_solar(p=SolarParameters(); tspan=(0.0,24.0), dt=1/60,
                   x0=p.μ, rng=MersenneTwister(590))

Simulate the proposal's cloud SDE and derived power. The default step is one
minute. Use smaller steps for numerical convergence studies. Cloud state is
simulated through the night, but generated electrical power is zero then.
"""
function simulate_solar(p::SolarParameters=SolarParameters();
                        tspan=(0.0, 24.0), dt=1 / 60,
                        x0=p.μ, rng=Random.MersenneTwister(590))
    validate(p)
    t0, tf = Float64.(tspan)
    isfinite(t0) && isfinite(tf) && tf > t0 ||
        throw(ArgumentError("Require finite start < end."))
    isfinite(dt) && dt > 0 || throw(ArgumentError("dt must be finite and positive."))
    isfinite(x0) && 0 < x0 < 1 || throw(ArgumentError("Require 0 < x0 < 1."))
    steps = ceil(Int, (tf - t0) / dt)
    time = collect(range(t0, tf; length=steps + 1))
    h = (tf - t0) / steps
    transmission = Vector{Float64}(undef, length(time))
    transmission[1] = x0
    if p.σ == 0
        transmission .= p.μ .+ (x0 - p.μ) .* exp.(-p.κ .* (time .- t0))
    else
        θ = 2asin(sqrt(x0))
        for i in 2:length(time)
            θ = cloud_step(θ, h, sqrt(h) * randn(rng), p)
            transmission[i] = sin(θ / 2)^2
        end
    end
    clear = clear_sky_power.(time, Ref(p))
    mean_transmission = p.μ .+ (x0 - p.μ) .* exp.(-p.κ .* (time .- t0))
    return (; time, transmission, clear, power=clear .* transmission,
            expected_power=clear .* mean_transmission)
end

"""Generate reproducible sample profiles and save both PNG and vector PDF."""
function plot_solar_profile(; p=SolarParameters(), seed=590, paths=3,
                            output_dir=joinpath(@__DIR__, "plots"))
    paths > 0 || throw(ArgumentError("paths must be positive."))
    samples = [simulate_solar(p; rng=MersenneTwister(seed + i - 1)) for i in 1:paths]
    first_sample = first(samples)
    Fieldline.apply_plots_defaults!()
    colors = Fieldline.categorical_palette()
    reference_color = Fieldline.categorical(:ink)
    power_plot = plot(; ylabel="Electrical power (W)",
        title="Solar power profile",
        xlims=(0, 24), ylims=(0, 1.08p.peak_power), legend=:topright)
    for (i, sample) in enumerate(samples)
        plot!(power_plot, sample.time, sample.power;
              label="Cloud realization $i", color=colors[mod1(i, length(colors))],
              alpha=0.8)
    end
    plot!(power_plot, first_sample.time, first_sample.clear;
          label="Clear sky", color=reference_color, linewidth=2.0, linestyle=:dash)
    plot!(power_plot, first_sample.time, first_sample.expected_power;
          label="Expected solar power", color=reference_color, linewidth=2.0, linestyle=:dot)
    cloud_plot = plot(; xlabel="Time of day (hours)", ylabel="Cloud transmission X",
        xlims=(0, 24), ylims=(0, 1), legend=false)
    for (i, sample) in enumerate(samples)
        plot!(cloud_plot, sample.time, sample.transmission;
              color=colors[mod1(i, length(colors))], alpha=0.8)
    end
    hline!(cloud_plot, [p.μ]; color=reference_color, linestyle=:dot)
    figure = plot(power_plot, cloud_plot; layout=(2, 1), size=(1100, 760),
                  link=:x, xticks=0:3:24, margin=5Plots.mm)
    mkpath(output_dir)
    png_path = joinpath(output_dir, "solar_profile.png")
    pdf_path = joinpath(output_dir, "solar_profile.pdf")
    savefig(figure, png_path)
    savefig(figure, pdf_path)
    return (; figure, samples, png_path, pdf_path)
end

# Including this file defines the reusable model; running it generates the plot.
if abspath(PROGRAM_FILE) == @__FILE__
    result = plot_solar_profile()
    println("Saved solar profile: ", result.png_path)
    println("Saved vector plot: ", result.pdf_path)
end
