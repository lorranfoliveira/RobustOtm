include("../src/RobustOtm.jl")

using Test

# ======================================
# Point
# ======================================
using .RobustFEA: Point, distance, Δcoords

@testset verbose = true "Point" begin
    @testset "Constructor_1" begin
        p = Point(1.0, 2.0)
        @test p.coords[1] == 1.0
        @test p.coords[2] == 2.0
    end

    @testset "Constructor_2" begin
        p = Point()
        @test p.coords[1] == 0.0
        @test p.coords[2] == 0.0
    end

    @testset "Δcoords" begin
        p1 = Point(1.1, 2.9)
        p2 = Point(3.0, 4.0)
        @test Δcoords(p1, p2) == [1.9, 1.1]
    end

    @testset "distance" begin
        p1 = Point()
        p2 = Point(3.0, 4.0)
        @test distance(p1, p2) == 5.0
    end
end


# ======================================
# Segment
# ======================================
using .RobustFEA: Segment, length, cos, sin, angle

@testset verbose = true "Segment" begin

    @testset "Constructor_1" begin
        p1 = Point(1.0, 2.0)
        p2 = Point(3.0, 4.0)
        s = Segment(p1, p2)

        @test s.p1.coords[1] == 1.0
        @test s.p1.coords[2] == 2.0
        @test s.p2.coords[1] == 3.0
        @test s.p2.coords[2] == 4.0
    end

    @testset "Constructor_2" begin
        s = Segment(1.0, 2.0, 3.0, 4.0)

        @test s.p1.coords[1] == 1.0
        @test s.p1.coords[2] == 2.0
        @test s.p2.coords[1] == 3.0
        @test s.p2.coords[2] == 4.0
    end

    @testset "length" begin
        s = Segment(1.0, 2.0, 3.0, 4.0)

        @test length(s) == 2.8284271247461903
    end

    @testset "cos" begin
        s = Segment(1.0, 2.0, 3.0, 4.0)
        @test cos(s) == 0.7071067811865475
    end

    @testset "sin" begin
        s = Segment(1.0, 2.0, 3.0, 4.0)
        @test sin(s) == 0.7071067811865475
    end

    @testset "angle" begin
        s = Segment(1.0, 2.0, 3.0, 4.0)
        @test angle(s) == 0.7853981633974483
    end
end