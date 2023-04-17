include("../fea/structure.jl")
using LinearAlgebra,
      SparseArrays


mutable struct Compliance
    structure::Structure
    p::Float64
    eig_vals
    eig_vecs

    function Compliance(structure::Structure, p::Float64=5.0)
        new(structure, p, [], [])
    end
end


function calculate_C_eigenvals_and_eigenvecs(compliance::Compliance)
    c::Matrix{Float64} = C(compliance)
    compliance.eig_vals, compliance.eig_vecs = eigen(c)
end


function diff_eigenvals(compliance::Compliance)
    num_eigvals::Int64 = length(compliance.eig_vals)
    num_design_vars::Int64 = length(compliance.structure.elements)
    dC::Vector{Matrix{Float64}} = diff_C(compliance)
    
    g::Matrix{Float64} = zeros(num_eigvals, num_design_vars)

    for i=1:num_eigvals
        vecs::Vector{Float64} = compliance.eig_vecs[:, i]

        for j=1:num_design_vars
            g[i, j] = vecs' * dC[j] * vecs
        end
    end

    return g
end

function obj(compliance::Compliance)::Float64
    return maximum(compliance.eig_vals)
end

function obj_smooth(compliance::Compliance)::Float64
    return norm(compliance.eig_vals, compliance.p)
end

function diff_obj(compliance::Compliance)
    return diff_eigenvals(compliance)[end, :]
end


function diff_obj_smooth(compliance::Compliance)
    calculate_C_eigenvals_and_eigenvecs(compliance)

    df_pnorm::Vector{Float64} = (compliance.eig_vals .^ (compliance.p - 1)) / (norm(compliance.eig_vals, compliance.p) ^ (compliance.p - 1))

    return df_pnorm' * diff_eigenvals(compliance)
end


function H(compliance::Compliance)
    s = compliance.structure
    fl_dofs = free_loaded_dofs(s)
    
    h = spzeros(number_of_dofs(s), length(fl_dofs))
    
    c::Int64 = 1
    for i in fl_dofs
        h[i, c] = 1.0
        c += 1
    end

    return h
end

function diff_K(element::Element)::SparseMatrixCSC{Float64}
    aux::Float64 = element.area
    element.area = 1.0
    k::SparseMatrixCSC{Float64} = spzeros(4, 4)
    
    free_dofs::Vector{Int64} = dofs(element, include_restricted=false, local_dofs=true)
    k[free_dofs, free_dofs] = K(element)[free_dofs, free_dofs]
    element.area = aux
    
    return k
end

diff_K(compliance::Compliance)::Vector{SparseMatrixCSC{Float64}} = [diff_K(element) for element in compliance.structure.elements]

function Z(compliance::Compliance)
    return K(compliance.structure) \ H(compliance)
end

function C(compliance::Compliance)::Matrix{Float64}
    z::Matrix{Float64} = Z(compliance)
    return z' * K(compliance.structure) * z
end 

function diff_C(compliance::Compliance)
    g::Vector{Matrix{Float64}} = []
    z::Matrix{Float64} = Z(compliance)

    for element in compliance.structure.elements
        ze::Matrix{Float64} = z[dofs(element, include_restricted=true), :]
        push!(g, -ze' * diff_K(element) * ze)
    end

    return g
end
