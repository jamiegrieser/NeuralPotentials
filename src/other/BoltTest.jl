using DifferentialEquations, Flux, DiffEqFlux, Zygote, Bolt, ForwardDiff
using Plots, Statistics, LinearAlgebra, LaTeXStrings, DataFrames, Distributions, Measures
include("../lib/SagittariusData.jl")
include("../lib/MechanicsDatasets.jl")
include("../lib/AwesomeTheme.jl")
using .SagittariusData
using .MechanicsDatasets

# Cₗ₌₁₀₀ function of baryon density
function cl100(Ω_b::DT) where DT
    par = CosmoParams{DT}(Ω_b=Ω_b)
    bg = Background(par)
    ih = IonizationHistory(Peebles(), par, bg)
    k_grid = quadratic_k(0.1bg.H₀, 1000bg.H₀, 10)
    sf = source_grid(par, bg, ih, k_grid, BasicNewtonian())
    return cltt(100, par, bg, ih, sf)
end

Δ = 1e-4
print("Result Comparison: ",
    (cl100(0.046 + Δ) - cl100(0.046 - Δ)) / 2Δ, " ",
    ForwardDiff.derivative(cl100, 0.046), "\n")

using BenchmarkTools
print("Simple Finite Difference:\n")
@btime (cl100(0.046 + Δ) - cl100(0.046 - Δ)) / 2Δ
print("ForwardDiff:\n")
@btime ForwardDiff.derivative(cl100, 0.046)

