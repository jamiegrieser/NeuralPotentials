using DifferentialEquations, Flux, DiffEqFlux, Zygote
using Plots, Statistics, LinearAlgebra, LaTeXStrings, DataFrames
include("SagittariusData.jl")
using .SagittariusData

### Sagittarius A* System ###
const c = 30.64 # centiparsec per year
const G = 4.49e-3 # gravitational constant in new units : (centi-parsec)^3 * yr^-2 * (10^6*M_solar)^-1
### Initialisation of the Sagittarius data ------------------------ #
path = joinpath(@__DIR__, "SagittariusData.csv")
S2data = SagittariusData.loadstar(path, "S2", timestamps=true)
S2 = SagittariusData.orbit(S2data)
S2 = unique!(SagittariusData.centerorbit(S2, sortby=:ϕ), [:ϕ])

S2.r = 100.0 .* S2.r
S2.x = 100.0 .* S2.x
S2.x_err = 100.0 .* S2.x_err
S2.y = 100.0 .* S2.y
S2.y_err = 100.0 .* S2.y_err

# S2max = S2[findall(x -> x > -π/6, S2.ϕ), :]
# S2min = S2[findall(x -> x ≤ -π/6, S2.ϕ), :]

# S2min.ϕ = S2min.ϕ .+ 2π


# S2 = outerjoin(S2max,S2min,on=[:r,:ϕ,:x,:x_err,:y,:y_err,:t])
# ϕ = S2.ϕ
# ϕspan = (minimum(ϕ), maximum(ϕ))
# ϕ0 = Array(range(ϕspan[1], ϕspan[2], length=200))

# ϕ = unique!(sort!(vcat(ϕ, ϕ0)))

# idx = []
# for φ in S2.ϕ
#     push!(idx, findall(x->x==φ, ϕ)[1]) 
# end

ϕ0span = (0.01, 2π-0.01)
ϕ0 = Array(range(ϕ0span[1], ϕ0span[2], length=144))
r0 = 2.0
true_v0 = sqrt(G*4.35/r0) # initial velocity
true_u0 = [1.0/r0, 0.0] 
true_p = [4.35/(1.2*true_v0*r0)^2]

function kepler!(du, u, p, ϕ)
    U = u[1]
    dU = u[2]

    du[1] = dU
    du[2] = G*p[1]-U # - G/c^2 * p[1] * U^2
end

problem = ODEProblem(kepler!, true_u0, ϕ0span, true_p)

@time data = Array(solve(problem, Tsit5(), saveat=ϕ0))

function transform(angles, r, φ)
    ι = angles[1]
    Ω = angles[2]
    ω = angles[3]

    δ = Ω - ω

    x = r.*cos.(φ)
    y = r.*sin.(φ)

    # display(plot(x, y, zeros(144)))

    X = ( cos(Ω)^2*(1-cos(ι)) + cos(ι) ) * x .+ cos(Ω)*sin(Ω)*(1-cos(ι)) * y
    Y = cos(Ω)*sin(Ω)*(1-cos(ι)) * x .+ ( sin(Ω)^2*(1-cos(ι)) + cos(ι) ) * y
    Z = -sin(Ω)*sin(ι) * x .+ cos(Ω)*sin(ι) * y

    # display(plot!(X, Y, Z))
    # display(plot!(X, Y, zeros(144), camera=(70,50)))

    R = sqrt.(X.^2 + Y.^2)
    ϕ = mod.(atan.(Y,X) .+ δ, 2π)
    return R, ϕ
end

function inversetransform(angles, r, φ)
    ι = angles[1]
    Ω = angles[2]
    ω = angles[3]

    δ = Ω - ω

    x = r.*cos.(φ.- δ)
    y = r.*sin.(φ.- δ)
    z = r.*sin.((Ω-π) .- (φ .- δ)).*tan(-ι)

    # display(plot!(x,y,z, label="recovered 3D trajectory"))

    X = ( cos(Ω)^2*(1-cos(ι)) + cos(ι) ) * x .+ cos(Ω)*sin(Ω)*(1-cos(ι)) * y .+ sin(Ω)*sin(ι) * z
    Y = cos(Ω)*sin(Ω)*(1-cos(ι)) * x .+ ( sin(Ω)^2*(1-cos(ι)) + cos(ι) ) * y .- cos(Ω)*sin(ι) * z
    ϕ = mod.(atan.(Y,X), 2π)

    # display(scatter!(X, Y, zeros(144), xlabel="x", ylabel="y"))

    R = sqrt.(X.^2 + Y.^2)
    return R, ϕ
end

p = [80/180*π, π/3, 0.0]
R, ϕ = transform(p, 1.0 ./data[1,:], ϕ0)

orbit = hcat(R, ϕ)
star = S2 # DataFrame(orbit, ["r", "ϕ"])

# starmax = star[findall(x -> x > 5π/4, star.ϕ), :]
# starmin = star[findall(x -> x ≤ 5π/4, star.ϕ), :]
# star = outerjoin(starmax,starmin,on=[:r,:ϕ])

### End -------------------------------------------------- #
dV = FastChain(
    FastDense(1, 32, tanh),
    FastDense(32, 8, tanh),
    FastDense(8, 2, tanh),
    FastDense(2, 1)
)
ps = vcat(rand(Float32, 4), initial_params(dV))


function neuralkepler!(du, u, p, ϕ)
    U = u[1]
    dU = u[2]

    du[1] = dU
    du[2] = dV(U, p)[1]-U
end

u0 = vcat(1.0/r0, ps[1])
ϕspan = (0.0, 2π)
prob = ODEProblem(neuralkepler!, u0, ϕspan, ps[5:end])

function resort(pred, θ)
    buf = Zygote.Buffer(pred)
    for j in 1:size(θ,1)
        idx = findall(x->x==θ[j], pred.t)[1]
        buf[:,j] = pred[:,idx]
    end
    return copy(buf)
end

function predict(params)
    s, θ = inversetransform(params[2:4].*π, star.r, star.ϕ)
    u0 = vcat(1.0/s[1], params[1])
    pred = solve(prob, Tsit5(), u0=u0, p=params[5:end], saveat=θ)
    # pred = resort(pred, θ)
    _R, _ϕ = transform(params[2:4].*π, 1 ./ pred[1,:], θ)
    return hcat(_R, _ϕ)
end

function loss(params) 
    pred = predict(params)
    return sum( (1.0 ./ pred[:,1] .- 1.0 ./ star.r).^2 ), pred
end

opt = ADAM(1e-2)

i = 0

cb = function(p,l,pred)
    println("Epoch: ", i)
    println("Loss: ", l)
    println("Initial conditions: ", p[1])
    println("Rotation angles: ", p[2:4])
    println("Angular fit: ", sum((star.ϕ .- pred[:,2]).^2))
    if i % 1 == 0
        orbit_plot = plot(cos.(pred[:,2]) .* pred[:,1], sin.(pred[:,2]) .* pred[:,1], # xlims=(-10.0, 10.0), ylims=(-10.0, 10.0),
                            label="fit using neural network",
                            xlabel=L"x\textrm{ coordinate in }10^{-2}pc",
                            ylabel=L"y\textrm{ coordinate in }10^{-2}pc",
                            title="position of the test mass and potential"
        )
        orbit_plot = scatter!(orbit_plot, star.r .* cos.(star.ϕ), star.r .* sin.(star.ϕ), label="rotated data")
        # orbit_plot = scatter!(orbit_plot, cos.(ϕ0)./data[1,:], sin.(ϕ0)./data[1,:], label="original data")
        orbit_plot = scatter!(orbit_plot, [cos.(star.ϕ[1]).*star.r[1]], [sin.(star.ϕ[1]).*star.r[1]], label="initial point")

        # Plotting the potential
        R0 = Array(range(0.3, 11.5, length=100))
        dv = map(u -> dV(u, p[5:end])[1], 1 ./ R0)
        # dv0 = map(u -> dV0(u, [4.152])[1], R0)
        dv0 = G*true_p[1] * ones(100)
        pot_plot = plot(1 ./ R0, dv, ylims=(-0.1, 0.5))
        pot_plot = plot!(pot_plot, 1 ./ R0, dv0)

        result_plot = plot(orbit_plot, pot_plot, layout=(2,1), size=(1600, 1200), legend=:bottomright)
        display(plot(result_plot))
    end
    global i+=1
    return false
    
end

@time result = DiffEqFlux.sciml_train(loss, ps, opt, cb=cb, maxiters=150000)

