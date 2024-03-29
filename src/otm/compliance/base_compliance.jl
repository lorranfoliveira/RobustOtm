include("../../fea/structure.jl")

using LinearAlgebra,
      SparseArrays

abstract type Compliance end

abstract type ComplianceSmooth <: Compliance end

"""
BaseCompliance object.

Attributes
----------
structure::Structure
    Structure object.
p::Float64
    p-norm parameter.
compliance_type::Int64
    0: Nominal compliance.
    1: Worst-case with exact compliance.
    2: Worst-case with p-norm smoothed compliance.
    3: Worst-case with mu-smoothed compliance.
eig_vals
    Eigenvalues of the C matrix.
eig_vecs
    Eigenvectors of the C matrix.
"""
mutable struct BaseCompliance <: Compliance
    structure::Structure
    eig_vals
    eig_vecs
    obj_k::Float64
    obj_km1::Float64
    obj_km2::Float64
    unique_loads_angle::Bool

    function BaseCompliance(structure::Structure; unique_loads_angle::Bool=false)
        new(structure, [], [], 0.0, 0.0, 0.0, unique_loads_angle)
    end
end


"""
Calculate the eigenvalues and eigenvectors of the C matrix and store them in the BaseCompliance.eig_vals and 
BaseCompliance.eig_vecs attributes.
"""
function calculate_C_eigenvals_and_eigenvecs(base::BaseCompliance)
    c::Matrix{Float64} = C(base)
    base.eig_vals, base.eig_vecs = eigen(c)
end


"""
Derivative of the eigenvalues of the C matrix with respect to the design variables.
"""
function diff_eigenvals(base::BaseCompliance)
    num_eigvals::Int64 = length(base.eig_vals)
    num_design_vars::Int64 = length(base.structure.elements)
    dC::Vector{Matrix{Float64}} = diff_C(base)
    
    g::Matrix{Float64} = zeros(num_eigvals, num_design_vars)

    for i=1:num_eigvals
        vecs::Vector{Float64} = base.eig_vecs[:, i]

        for j=1:num_design_vars
            g[i, j] = vecs' * dC[j] * vecs
        end
    end

    return g
end

"""
Matrix that maps the complete forces vector to the loaded forces vector.
"""
function H(base::BaseCompliance)::Matrix{Float64}
    fl_dofs = free_loaded_dofs(base.structure)

    f = forces(base.structure; include_restricted=true)
    
    h = zeros(number_of_dofs(base.structure), ifelse(base.unique_loads_angle, 2, length(fl_dofs)))
    
    c::Int64 = 1
    for i in fl_dofs
        cm = c
        if base.unique_loads_angle
            if isodd(cm)
                cm = 1
            else
                cm = 2
            end
        end

        h[i, cm] = f[i]
        c += 1
    end

    return h[dofs(base.structure), :]
end

"""
Derivative of stiffness matrix of element with respect to the design variables.
"""
function diff_K(element::Element)::SparseMatrixCSC{Float64}
    aux::Float64 = element.area
    element.area = 1.0
    k::SparseMatrixCSC{Float64} = spzeros(4, 4)
    
    free_dofs::Vector{Int64} = dofs(element, include_restricted=false, local_dofs=true)
    k[free_dofs, free_dofs] = K(element)[free_dofs, free_dofs]
    element.area = aux
    
    return k
end

"""
Derivative of the stiffness matrix of the structure with respect to the design variables.
"""
diff_K(base::BaseCompliance)::Vector{SparseMatrixCSC{Float64}} = [diff_K(element) for element in base.structure.elements]

"""
Auxiliar matrix Z.
"""
function Z(base::BaseCompliance)
    h = H(base)
    z::Matrix{Float64} = zeros(number_of_dofs(base.structure), size(h)[2])
    z[dofs(base.structure, include_restricted=false), :] = K(base.structure) \ H(base)
    return z
end

"""
Matrix where the eigenvalues are extracted from.
"""
function C(base::BaseCompliance)::Matrix{Float64}
    z::Matrix{Float64} = Z(base)
    df = dofs(base.structure, include_restricted=false)
    return z[df,:]' * K(base.structure) * z[df,:]
end 

"""
Derivative of C matrix.
"""
function diff_C(base::BaseCompliance)
    g::Vector{Matrix{Float64}} = []
    z = Z(base)

    for element in base.structure.elements
        ze::Matrix{Float64} = z[dofs(element, include_restricted=true), :]
        push!(g, -ze' * diff_K(element) * ze)
    end

    return g
end

function forces(base::BaseCompliance)
    f = zeros(number_of_dofs(base.structure))
    f[dofs(base.structure)] = H(base) * base.eig_vecs[:, end]
    return f
end
