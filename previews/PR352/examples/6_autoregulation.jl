using DataDrivenDiffEq
using ModelingToolkit
using OrdinaryDiffEq
using LinearAlgebra

@parameters begin
    t
    α = 1.0
    β = 1.3
    γ = 2.0
    δ = 0.5
end

@variables begin
    x[1:2](t) = [20.0; 12.0]
end

x = collect(x)
D = Differential(t)

eqs = [
    D(x[1]) ~ α/(1+x[2])-β*x[1];
    D(x[2]) ~ γ/(1+x[1])-δ*x[2];
]

sys = ODESystem(eqs, t, x, [α, β, γ, δ], name = :Autoregulation)

x0 = [x[1] => 20.0; x[2] => 12.0]

tspan = (0.0, 5.0)

de_problem = ODEProblem(sys, x0, tspan)
de_solution = solve(de_problem, Tsit5(), saveat = 0.005);

dd_prob = ContinuousDataDrivenProblem(de_solution)

eqs = [
    polynomial_basis(x, 4); D.(x); x .* D(x[1]); x .* D(x[2])
    ]

basis = Basis(eqs, x, independent_variable = t, implicits = D.(x))

sampler = DataSampler(
    Split(ratio = 0.8), Batcher(n = 10, shuffle = true, repeated = true, batchsize_min = 30)
)

res = solve(dd_prob, basis, ImplicitOptimizer(STLSQ(1e-1:1e-1:9e-1)), by = :min, sampler = sampler, digits = 1)
print(res) #hide
print(result(res)) #hide

system = result(res)
@named ode = ODESystem(equations(system), t, x, parameters(system));
ode_prob = ODEProblem(ode, x0, tspan, parameter_map(res));

prediction = solve(ode_prob, Tsit5(), saveat = 0.2);

# This file was generated using Literate.jl, https://github.com/fredrikekre/Literate.jl
