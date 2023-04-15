include("../../src/fea/structure.jl")

using Test

@testset verbose=true "Structure" begin
    nodes = [
        Node(1, [1.0, -1.0]; constraint=[true, true]),
        Node(2, [3.0, -1.0]),
        Node(3, [5.0, -1.0]),
        Node(4, [7.0, -1.0]; constraint=[true, true]),
        Node(5, [3.0, 1.0]; force=[10.0, -5.0]),
        Node(6, [5.0, 1.0])
    ]

    material = Material(1, 100e6)

    area = 0.0014
    elements = [
        Element(1, area, [nodes[1], nodes[2]], material),
        Element(2, area, [nodes[1], nodes[5]], material),
        Element(3, area, [nodes[2], nodes[3]], material),
        Element(4, area, [nodes[2], nodes[6]], material),
        Element(5, area, [nodes[4], nodes[3]], material),
        Element(6, area, [nodes[5], nodes[2]], material),
        Element(7, area, [nodes[5], nodes[6]], material),
        Element(8, area, [nodes[6], nodes[3]], material),
        Element(9, area, [nodes[6], nodes[4]], material)
    ]

    structure = Structure(nodes, elements)

    @testset "Constructor" begin
        nds::Vector{Node} = []
        els::Vector{Element} = []
        @test_throws ArgumentError Structure(nds, elements)
        @test_throws ArgumentError Structure(nodes, els)
    end

    @testset "number_of_dofs" begin
        @test number_of_dofs(structure) == 12
    end

    @testset "constraint" begin
        @test constraint(structure) == [true, true, false, false, false, false, true, true, false, false, false, false]
    end

    @testset "dofs" begin
        @test dofs(structure) == [3, 4, 5, 6, 9, 10, 11, 12]
        @test dofs(structure, include_restricted=true) == Vector(1:12)
    end

    @testset "free_loaded_dofs" begin
        @test free_loaded_dofs(structure) == [9, 10]
    end
    
    @testset "forces" begin
        @test forces(structure) == [0.0, 0.0, 0.0, 0.0, 10.0, -5.0, 0.0, 0.0]
        @test forces(structure, include_restricted=true) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0, -5.0, 0.0, 0.0]
        @test forces(structure, exclude_zeros=true) == [10.0, -5.0]
        @test forces(structure, include_restricted=true, exclude_zeros=true) == [10.0, -5.0]
    end

    @testset "K" begin
        kt = sparse([0.00011224873734152916 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0; 
                     0.0 0.00011224873734152916 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0; 
                     0.0 0.0 164748.7374537779 24748.73734152916 -70000.0 0.0 0.0 0.0 -2.624579619658251e-28 4.2862637970157364e-12 -24748.737341529166 -24748.737341529162; 
                     0.0 0.0 24748.737341529155 94748.73745377788 0.0 0.0 0.0 0.0 4.2862637970157364e-12 -70000.0 -24748.73734152916 -24748.737341529155; 
                     0.0 0.0 -70000.0 0.0 140000.00011224873 -1.285879139104721e-11 0.0 0.0 0.0 0.0 -2.624579619658251e-28 4.2862637970157364e-12; 
                     0.0 0.0 0.0 0.0 -1.285879139104721e-11 70000.00011224873 0.0 0.0 0.0 0.0 4.2862637970157364e-12 -70000.0; 
                     0.0 0.0 0.0 0.0 0.0 0.0 0.00011224873734152916 0.0 0.0 0.0 0.0 0.0; 
                     0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.00011224873734152916 0.0 0.0 0.0 0.0; 
                     0.0 0.0 -2.624579619658251e-28 4.2862637970157364e-12 0.0 0.0 0.0 0.0 94748.7374537779 24748.73734152916 -70000.0 0.0; 
                     0.0 0.0 4.2862637970157364e-12 -70000.0 0.0 0.0 0.0 0.0 24748.737341529155 94748.73745377788 0.0 0.0; 
                     0.0 0.0 -24748.737341529166 -24748.737341529162 -2.624579619658251e-28 4.2862637970157364e-12 0.0 0.0 -70000.0 0.0 119497.47479530706 -3.637978807091713e-12; 
                     0.0 0.0 -24748.73734152916 -24748.737341529155 4.2862637970157364e-12 -70000.0 0.0 0.0 0.0 0.0 -3.637978807091713e-12 119497.47479530703])

        @test K(structure) ≈ kt
    end

    @testset "u" begin
        @test u(structure) ≈ [
            0.0,
            0.0,
            4.761904761904763e-5,
            -0.00019817906943235845,
            2.3809523809523814e-5,
            -7.528001090665546e-5,
            0.0,
            0.0,
            0.0002696076408609297,
            -0.0002696076408609298,
            0.00012675049800378677,
            -7.528001090665545e-5,
        ]
    end
end