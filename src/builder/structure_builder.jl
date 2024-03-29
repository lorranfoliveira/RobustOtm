include("../../src/fea/fea.jl")

using LinearAlgebra

mutable struct StructureBuilder
    lx::Float64
    ly::Float64
    nx::Int64
    ny::Int64
    connectivity_ratio::Float64
    material::Material
    nodes_matrix::Matrix{Float64}
    elements_matrix::Matrix{Int64}

    function StructureBuilder(lx::Float64, ly::Float64, nx::Int64, ny::Int64, material::Material; connectivity_ratio::Float64=Inf)
        nodes_matrix = zeros(Float64, nx * ny, 2)
        elements_matrix = zeros(Int64, 0, 2)
        ef_ratio = max(connectivity_ratio, (1.0 + 1e-10) * sqrt((lx / (nx - 1))^2 + (ly / (ny - 1))^2))

        new(lx, ly, nx, ny, ef_ratio, material, nodes_matrix, elements_matrix)
    end
end

dx(builder::StructureBuilder) = builder.lx / (builder.nx - 1)

dy(builder::StructureBuilder) = builder.ly / (builder.ny - 1)

function build_nodes!(builder::StructureBuilder)
    lx = builder.lx
    ly = builder.ly
    nx = builder.nx
    ny = builder.ny

    k = 1
    for i in 1:ny
        for j in 1:nx
            builder.nodes_matrix[k, 1] = (j - 1) * dx(builder)
            builder.nodes_matrix[k, 2] = builder.ly - (i - 1) * dy(builder)
            k += 1
        end
    end
end

function determinant_3x3(builder::StructureBuilder, nodes_ids::Vector{Int64})
    if length(nodes_ids) != 3
        throw(ArgumentError("The number of nodes must be 3"))
    end

    a, b = builder.nodes_matrix[nodes_ids[1], :]
    c = 1
    d, e = builder.nodes_matrix[nodes_ids[2], :]
    f = 1
    g, h = builder.nodes_matrix[nodes_ids[3], :]
    i = 1

	return (a * e * i) + (b * f * g) + (c * d * h) - (c * e * g) - (b * d * i) - (a * f * h)
end

function is_collinear(builder::StructureBuilder, element1::Vector{Int64}, element2::Vector{Int64})
    if length(element1) != 2 || length(element2) != 2
        throw(ArgumentError("The number of nodes must be 2"))
    end

    det1 = determinant_3x3(builder, [element1[1], element1[2], element2[1]])
    det2 = determinant_3x3(builder, [element1[1], element1[2], element2[2]])

    return isapprox(det1, 0.0, atol=1e-10) && isapprox(det2, 0.0, atol=1e-10)
end

function is_overlap(builder::StructureBuilder, element1::Vector{Int64}, element2::Vector{Int64})
    if is_collinear(builder, element1, element2)
        nodes = builder.nodes_matrix[vcat(element1, element2), :]
        l1 = norm(nodes[1, :] - nodes[2, :])
        l2 = norm(nodes[3, :] - nodes[4, :])

        dmax = maximum([norm(nodes[i,:] - nodes[j, :]) for i=1:size(nodes)[1] for j=1:size(nodes)[1] if i!=j])

        return dmax < l1 + l2 && !isapprox(dmax, l1 + l2, atol=1e-10)
    else
        return false
    end
end

function build_elements!(builder::StructureBuilder)
    @info "================== Building ground structure =================="
    n = builder.nx * builder.ny
    for i=1:n
        for j=1:n
            if i != j
                dist = norm(builder.nodes_matrix[i, :] - builder.nodes_matrix[j, :])
                if dist ≤ builder.connectivity_ratio
                    el_ref = [i, j]
                    sz_els_matrix = size(builder.elements_matrix)[1]

                    if sz_els_matrix == 0
                        builder.elements_matrix = vcat(builder.elements_matrix, el_ref')
                        continue
                    end
                    
                    overlaps = false
                    for el2_id=1:sz_els_matrix
                        el2 = builder.elements_matrix[el2_id, :]

                        if is_overlap(builder, el_ref, el2)
                            overlaps = true
                            break
                        end

                    end
                    
                    if !overlaps
                        builder.elements_matrix = vcat(builder.elements_matrix, el_ref')
                    end
                end
            end
            @info "Generating elements: $(round((n * (i - 1) + j) / (n^2) * 100, digits=3)) %"
        end
    end

    @info "----------------------------------------------------------------------"
    @info "Ground Structure built with $(size(builder.elements_matrix)[1]) elements and $(size(builder.nodes_matrix)[1]) nodes!\n"
    @info "----------------------------------------------------------------------"
end

function build(builder::StructureBuilder)::Structure
    build_nodes!(builder)
    build_elements!(builder)

    nodes = [Node(i, builder.nodes_matrix[i, :]) for i in 1:size(builder.nodes_matrix)[1]]
    elements = [Element(i, nodes[builder.elements_matrix[i, :]], builder.material) for i=1:size(builder.elements_matrix)[1]]

    return Structure(nodes, elements)
end
