# A wrapper for Distribution type to support parameters in Dual type
# by calling hand-written density functions.

# NOTE: Principle 1 - only store parameters as Dual but not produce Dual. This ensures compatibility of HMC and other samplers.

import Distributions: pdf, rand
import Base: gradient
export dDistribution, dBernoulli, hmcBernoulli, dCategorical, hmcCategorical, dNormal, hmcNormal, dMvNormal, hmcMvNormal, dTDist, hmcTDist, dExponential, hmcExponential, dGamma, hmcGamma, dInverseGamma, hmcInverseGamma, dBeta, hmcBeta, logpdf

using PDMats

abstract dDistribution

function pdf(dd :: dDistribution, x :: Real)
  return pdf(dd.d, x)
end

function pdf(dd :: dDistribution, x :: Dual)
  return dd.df(x)
end

function pdf(dd :: dDistribution, x :: Vector)
  if isa(x[1], Dual)
    return dd.df(x)
  else
    return pdf(dd.d, x)
  end
end

function logpdf(dd :: dDistribution, x :: Real)
  return logpdf(dd.d, x)
end

function rand(dd :: dDistribution)
  return rand(dd.d)
end

function gradient(dd :: dDistribution, x)
  if isa(x, Vector)
    l = length(x)
    x_dual = []
    for i = 1:l
      push!(x_dual, make_dual(l, x[i], i))
    end
    return dualpart(pdf(dd, x_dual))
  else
    x = isa(x, Dual)? x : Dual(x)
    x = Dual(realpart(x), 1)
    return dualpart(pdf(dd, x))[1]
  end
end

###############################
# Distributions over integers #
###############################

# function hmcBinomial(f, N)
#   return r::Int64 -> factorial(N) / (factorial(r) * factorial(N - r)) * f^r * (1 - f)^(N - r)
# end

# Bernoulli
type dBernoulli <: dDistribution
  p     ::    Dual
  d     ::    Bernoulli
  df    ::    Function
  function dBernoulli(p)
    # Convert Real to Dual if possible
    # Force Float64 inside Dual to avoid a known bug of Dual
    p = isa(p, Dual)? p : Dual(p)
    d = Bernoulli(realpart(p))
    df = hmcBernoulli(p)
    new(p, d, df)
  end
end

function hmcBernoulli(p)
  return k -> p^k * (1 - p)^(1 - k)
end

# Categorical
type dCategorical <: dDistribution
  p     ::    Vector{Dual}
  d     ::    Categorical
  df    ::    Function
  function dCategorical(p::Vector)
    # Convert Real to Dual if possible
    # Force Float64 inside Dual to avoid a known bug of Dual
    p = isa(p[1], Dual)? p : map(x -> Dual(x), p)
    d = Categorical(realpart(p))
    df = hmcCategorical(p)
    new(p, d, df)
  end
  function dCategorical(n::Int64)
    p = ones(n) / n
    p = isa(p[1], Dual)? p : map(x -> Dual(x), p)
    d = Categorical(realpart(p))
    df = hmcCategorical(p)
    new(p, d, df)
  end
end

function hmcCategorical(p)
  return k -> p[realpart(k)]  # this function will only be called when k is Dual
end

# function hmcPoisson(λ)
#   return r::Int64 -> exp(-λ) * λ^r / factorial(r)
# end

# function hmcExponentialInt(f)
#   return r::Int64 -> (1 - f) * exp(-ln(1 / f) * r)
# end

# #############################################
# # Distributions over unbounded real numbers #
# #############################################

# Normal
type dNormal <: dDistribution
  μ     ::    Dual
  σ     ::    Dual
  d     ::    Normal
  df    ::    Function
  function dNormal(μ, σ)
    # Convert Real to Dual if possible
    # Force Float64 inside Dual to avoid a known bug of Dual
    μ = isa(μ, Dual)? μ : Dual(μ)
    σ = isa(σ, Dual)? σ : Dual(σ)
    d = Normal(realpart(μ), realpart(σ))
    df = hmcNormal(μ, σ)
    new(μ, σ, d, df)
  end
end

function hmcNormal(μ, σ)
  return x -> 1 / sqrt(2pi * σ^2) * exp(-0.5 * (x - μ)^2 / σ^2)
end

# Multivariate normal
type dMvNormal <: dDistribution
  μ     ::    Vector{Dual}
  Σ     ::    Array{Dual, 2}
  d     ::    MvNormal
  df    ::    Function
  function dMvNormal(μ, Σ)
    # Convert Real to Dual if possible
    μ = isa(μ[1], Dual)? μ : map(x -> Dual(x), μ)
    Σ = isa(Σ[1, 1], Dual)? Σ : map(x -> Dual(x), Σ)
    # The constructor of MvNormal requires the Σ to be a type of PDMat
    d = MvNormal(forceVector(realpart(μ), Float64), PDMat(realpart(Σ)))
    df = hmcMvNormal(μ, Σ)
    new(μ, Σ, d, df)
  end
end

function hmcMvNormal(μ, Σ)
  Λ = inv(Σ)
  return x -> 1 / sqrt((2pi)^2 * det(Σ)) * exp(-0.5 * ((x - μ)' * Λ * (x - μ))[1])
end

# StudentT
type dTDist <: dDistribution
 ν     ::    Dual
 d     ::    TDist
 df    ::    Function
 function dTDist(ν)
   # Convert Real to Dual if possible
   ν = isa(ν, Dual)? ν : Dual(ν)
   d = TDist(realpart(ν))
   df = hmcTDist(ν)
   new(ν, d, df)
 end
end

function hmcTDist(ν)
  Z = sqrt(pi * ν) * gamma(ν / 2) / gamma((ν + 1) / 2)
  return x -> 1 / Z * 1 / (1 + x^2 / ν)^((ν + 1) / 2)
end

# function hmcBiexponential(μ, s)
#   return x::Real -> 1 / 2s * exp(-abs(x - μ) / s)
# end

# function hmcInverseCosh(β)
#   return x::Real -> 1 / cosh(β * x)^(1 / β)
# end

# ############################################
# # Distributions over positive real numbers #
# ############################################

# Exponential
type dExponential <: dDistribution
 Θ     ::    Dual
 d     ::    Exponential
 df    ::    Function
 function dExponential(Θ)
   # Convert Real to Dual if possible
   Θ = isa(Θ, Dual)? Θ : Dual(Θ)
   d = Exponential(realpart(Θ))
   df = hmcExponential(Θ)
   new(Θ, d, df)
 end
end

function hmcExponential(Θ)
  return x -> 1 / Θ * exp(-x / Θ)
end

# Gamma
type dGamma <: dDistribution
  α     ::    Dual
  Θ     ::    Dual
  d     ::    Gamma
  df    ::    Function
  function dGamma(α, Θ)
    # Convert Real to Dual if possible
    α = isa(α, Dual)? α : Dual(α)
    Θ = isa(Θ, Dual)? Θ : Dual(Θ)
    d = Gamma(realpart(α), realpart(Θ))
    df = hmcGamma(α, Θ)
    new(α, Θ, d, df)
  end
end

function hmcGamma(α, Θ)
  return x -> 1 / (gamma(α) * Θ) * (x / Θ)^(α - 1) * exp(-x / Θ)
end

# InverseGamma
type dInverseGamma <: dDistribution
  α     ::    Dual
  Θ     ::    Dual
  d     ::    InverseGamma
  df    ::    Function
  function dInverseGamma(α, Θ)
    # Convert Real to Dual if possible
    α = isa(α, Dual)? α : Dual(α)
    Θ = isa(Θ, Dual)? Θ : Dual(Θ)
    d = InverseGamma(realpart(α), realpart(Θ))
    df = hmcInverseGamma(α, Θ)
    new(α, Θ, d, df)
  end
end

function hmcInverseGamma(α, Θ)
  # NOTE: There is a bug of Dual type, where "Dual(1, 0) ^ Dual(-3, 0)" gives error
  return x -> (Θ^α) / gamma(α) * x^(-α - 1) * exp(-Θ / x)
end

# function hmcLogNormal(m, s)
#   Z = sqrt(2pi * s^2)
#   return x -> 1 / x * 1 / Z * exp(-(ln(x) - ln(m))^2 / (2 * s^2))
# end

# #########################################
# # Distributions over periodic variables #
# #########################################

# function hmcVonMises(μ, β)
#   return Θ -> 1 / (2pi * besselj0(β)) * exp(β * cos(Θ - μ))
# end

# ####################################
# # Distributions over probabilities #
# ####################################

# Beta
type dBeta <: dDistribution
  α     ::    Dual
  β     ::    Dual
  d     ::    Beta
  df    ::    Function
  function dBeta(α, β)
    # Convert Real to Dual if possible
    α = isa(α, Dual)? α : Dual(α)
    β = isa(β, Dual)? β : Dual(β)
    d = Beta(realpart(α), realpart(β))
    df = hmcBeta(α, β)
    new(α, β, d, df)
  end
end

function hmcBeta(α, β)
  Z = gamma(α) * gamma(β) / (gamma(α + β))
  return x -> 1 / Z * x^(α - 1) * (1 - x)^(β - 1)
end
hmcBeta(1,1)(0.9)
# function hmcDirichelet(u...)
#   Z = sum(map(gamma, u)) / gamma(sum(u))
#   function pdf(p...)
#     1 / Z * prod(p .^ (u - 1)) * (sum(p) == 1)
#   end
#   return pdf
# end
