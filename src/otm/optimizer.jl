include("compliance/compliance.jl")

using JSON, Statistics

mutable struct Optimizer
    # manual
    compliance::T where {T<:Compliance}
    filename::String
    volume_max::Float64
    use_adaptive_move::Bool
    use_adaptive_damping::Bool
    min_iters::Int64
    max_iters::Int64
    x_min::Float64
    tol::Float64
    damping::Float64
    output::Dict{String, Any}

    # automatic
    x_max::Float64
    x_init::Float64
    move::Vector{Float64}
    iter::Int64
    n::Int64

    x_k::Vector{Float64}
    x_km1::Vector{Float64}
    x_km2::Vector{Float64}

    df_obj_k::Vector{Float64}
    df_obj_km1::Vector{Float64}
    df_obj_km2::Vector{Float64}

    df_vol::Vector{Float64}

    vol::Float64

    layout_constraint::Union{Matrix{Int64},Nothing}
    layout_constraint_divisions::Union{Int}

    function Optimizer(compliance::T, filename::String; volume_max::Float64=1.0,
        initial_move_parameter::Float64=1.0,
        use_adaptive_move::Bool=true,
        use_adaptive_damping::Bool=true,
        min_iters::Int64=20,
        max_iters::Int64=5000,
        x_min::Float64=1e-12,
        tol::Float64=1e-8,
        damping::Float64=0.0,
        layout_constraint::Union{Matrix{Int64},Nothing}=nothing,
        layout_constraint_divisions::Union{Int}=0) where {T<:Compliance}

        els_len = [len(el) for el in compliance.base.structure.elements]
        n = length(compliance.base.structure.elements)

        x_max = volume_max / minimum(els_len)
        x_init = volume_max / sum(els_len)
        move = initial_move_parameter * fill(x_init, n)
        iter = 1

        x_k = fill(x_init, n)
        x_km1 = zeros(n)
        x_km2 = zeros(n)

        df_obj_k = zeros(n)
        df_obj_km1 = zeros(n)
        df_obj_km2 = zeros(n)

        df_vol_init = zeros(n)

        vol = 0.0

        new(compliance,
            filename,
            volume_max,
            use_adaptive_move,
            use_adaptive_damping,
            min_iters,
            max_iters,
            x_min,
            tol,
            damping,
            Dict{String, Any}(),
            x_max,
            x_init,
            move,
            iter,
            n,
            x_k,
            x_km1,
            x_km2,
            df_obj_k,
            df_obj_km1,
            df_obj_km2,
            df_vol_init,
            vol,
            layout_constraint,
            layout_constraint_divisions)
    end
end

function generate_optimizer(filename::String)::Optimizer
    # =================== Read data ===================
    data = JSON.parsefile(filename)

    # =================== Create structure ===================
    nodes::Vector{Node} = []
    elements::Vector{Element} = []
    materials::Vector{Material} = []

    for material_data in data["input_structure"]["materials"]
        material = Material(material_data["id"], material_data["young"])
        push!(materials, material)
    end

    for node_data in data["input_structure"]["nodes"]
        node = Node(node_data["id"], 
                    Vector{Float64}(node_data["position"]), 
                    force=Vector{Float64}(node_data["force"]), 
                    constraint=Vector{Bool}(node_data["support"]))
        push!(nodes, node)
    end

    for element_data in data["input_structure"]["elements"]
        id = element_data["id"]
        node1 = nodes[element_data["nodes"][1]]
        node2 = nodes[element_data["nodes"][2]]
        material = materials[element_data["material"]]
        element = Element(id, [node1, node2], material, element_data["area"])
        push!(elements, element)
    end

    structure = Structure(nodes, elements)
    
    # =================== Create optimizer ===================
    comp = NaN
    if data["optimizer"]["compliance_p_norm"]["use"]
        comp = ComplianceSmoothPNorm(structure, 
                                        p=data["optimizer"]["compliance_p_norm"]["p"],
                                        unique_loads_angle=false)
    end
    if data["optimizer"]["compliance_nominal"]["use"]
        if comp === NaN
            comp = ComplianceNominal(structure)
        else
            throw(ArgumentError("Only one compliance type can be used."))
        end
    end
    if data["optimizer"]["compliance_mu"]["use"]
        if comp === NaN
            comp = ComplianceSmoothMu(structure, β=data["optimizer"]["compliance_mu"]["beta"])
        else
            throw(ArgumentError("Only one compliance type can be used."))
        end
    end

    return Optimizer(comp, 
                    filename,
                    volume_max=data["optimizer"]["volume_max"],
                    initial_move_parameter=data["optimizer"]["initial_move_multiplier"],
                    use_adaptive_move=data["optimizer"]["use_adaptive_move"],
                    min_iters=data["optimizer"]["min_iterations"],
                    max_iters=data["optimizer"]["max_iterations"],
                    x_min=data["optimizer"]["x_min"],
                    tol=data["optimizer"]["tolerance"],
                    damping=data["optimizer"]["initial_damping_parameter"])
end

function consider_layout_constraint!(opt::Optimizer)
    if opt.layout_constraint === nothing
        return
    else
        for i = 1:size(opt.layout_constraint, 1)
            els = [el for el in opt.layout_constraint[i, :] if el != 0]
            opt.df_obj_k[els] .= sum(opt.df_obj_k[els])
            opt.df_vol[els] .= sum(opt.df_vol[els])
        end
    end
end

function automatic_layout_constraint!(opt::Optimizer)
    if opt.layout_constraint_divisions > 0
        n = length(opt.x_k) / opt.layout_constraint_divisions
        n = Int64(ceil(ifelse(ceil(n) <= n, n, ceil(n))))

        sort_x_index = zeros(n * opt.layout_constraint_divisions)
        sort_x_index[1:length(opt.x_k)] = sortperm(opt.x_k)
        sort_x_index = reshape(sort_x_index, n, opt.layout_constraint_divisions)'

        opt.layout_constraint = sort_x_index

        opt.x_k .= opt.x_init
    end
end

get_areas(opt::Optimizer)::Vector{Float64} = [el.area for el in opt.compliance.base.structure.elements]

function set_areas(opt::Optimizer)
    for i = eachindex(opt.compliance.base.structure.elements)
        opt.compliance.base.structure.elements[i].area = opt.x_k[i]
    end
end

diff_vol(opt::Optimizer) = [len(el) for el in opt.compliance.base.structure.elements]

function update_move!(opt::Optimizer)
    if opt.iter ≤ 2
        return
    else
        move_tmp = opt.move[:]

        terms = (opt.x_k - opt.x_km1) .* (opt.x_km1 - opt.x_km2)
        for i = eachindex(terms)
            if terms[i] < 0
                move_tmp[i] = 0.7 * opt.move[i]
            elseif terms[i] > 0
                move_tmp[i] = 1.2 * opt.move[i]
            end
        end

        opt.move = max.(1e-2 * opt.x_init, min.(move_tmp, 1000 * opt.x_init))
    end
end

function update_damping!(opt::Optimizer)
    if opt.iter % 50 == 0
        obj_k = opt.compliance.base.obj_k
        obj_km1 = opt.compliance.base.obj_km1
        obj_km2 = opt.compliance.base.obj_km2
        p = (obj_k - obj_km1) * (obj_km1 - obj_km2)
        for i = eachindex(p)
            if p < 0
                opt.damping = opt.damping + 0.025
            elseif p[i] > 0
                opt.damping = opt.damping - 0.025
            end
        end

        opt.damping = max(0.0, min(opt.damping, 0.98))
    end
end


function update_x!(opt::Optimizer)
    opt.vol = volume(opt.compliance.base.structure)
    opt.df_obj_k = diff_obj(opt.compliance)
    opt.df_vol = diff_vol(opt)

    consider_layout_constraint!(opt)

    if opt.use_adaptive_damping
        update_damping!(opt)
    end

    if opt.use_adaptive_move
        update_move!(opt)
    end


    η = 0.5

    #if opt.iter <= 2
    #    η = 0.5
    ##else
    #    ratio_diff = abs.(opt.df_obj_km1 ./ opt.df_obj_k)
    #    ratio_x = @. (opt.x_km2 + opt.tol) / (opt.x_km1 + opt.tol)
    #    a = @. 1 + log(ratio_diff) / log(ratio_x)
    #    a = max.(min.(map(v -> ifelse(v === NaN, 0, v), a), -2.0), -15)
    #    η = @. 1 / (1 - a)
    #end

    bm = -opt.df_obj_k ./ opt.df_vol
    l1 = 0.0
    l2 = 1.2 * maximum(bm)
    x_new = zeros(opt.n)

    while l2 - l1 > opt.tol * (l2 + 1)
        lm = (l1 + l2) / 2
        be = max.(0.0, bm / lm)
        xt = @. opt.x_min + (opt.x_k - opt.x_min) * be^η
        x_new = @. max(max(min(min(xt, opt.x_k + opt.move), opt.x_max), opt.x_k - opt.move), opt.x_min)
        if (opt.vol - opt.volume_max) + opt.df_vol' * (x_new - opt.x_k) > 0
            l1 = lm
        else
            l2 = lm
        end
    end

    x_new = opt.damping * opt.x_k + (1 - opt.damping) * x_new

    opt.x_k = x_new[:]
    set_areas(opt)
end

function add_output_data(opt::Optimizer)
    save_data = "save_data"
    iterations = "iterations"

    it_dict = Dict{String, Any}()

    if opt.iter % opt.output[save_data]["step"] == 0
        if opt.output[save_data]["save_areas"]
            it_dict["areas"] = get_areas(opt)
        end

        if opt.output[save_data]["save_forces"]
            it_dict["forces"] = forces(opt.compliance.base)
        end

        if opt.output[save_data]["save_compliance"]
            it_dict["compliance"] = obj(opt.compliance)
        end

        if opt.output[save_data]["save_volume"]
            it_dict["volume"] = opt.vol
        end

        if opt.output[save_data]["save_move"]
            it_dict["move"] = opt.move
        end

        if !isempty(it_dict)
            it_dict["id"] = opt.iter

            try
                push!(opt.output[iterations], it_dict)
            catch
                opt.output[iterations] = [it_dict]
            end
        end
    end
end

function optimize!(opt::Optimizer)
    opt.output = JSON.parsefile(opt.filename)
    error = Inf
    opt.iter = 0
    set_areas(opt)

    while error > opt.tol && opt.iter < opt.max_iters
        if opt.layout_constraint_divisions ≥ 1 #&& opt.iter % 500 == 0 && opt.iter > 0
            @warn "Applying automatic layout constraint"
            automatic_layout_constraint!(opt)
        end

        x_k_tmp = copy(opt.x_k)

        update_x!(opt)

        opt.compliance.base.obj_km2 = opt.compliance.base.obj_km1
        opt.compliance.base.obj_km1 = opt.compliance.base.obj_k

        opt.compliance.base.obj_k = obj(opt.compliance)

        opt.df_obj_km2 = copy(opt.df_obj_km1)
        opt.df_obj_km1 = copy(opt.df_obj_k)
        opt.x_km2 = copy(opt.x_km1)
        opt.x_km1 = copy(x_k_tmp)

        add_output_data(opt)

        error = ifelse(opt.iter <= opt.min_iters, Inf, norm((opt.x_k - opt.x_km1) ./ (1 .+ opt.x_km1), Inf))

        @info "It: $(opt.iter)  obj: $(obj(opt.compliance)) mean_move: $(mean(opt.move)) γ:$(opt.damping)  vol: $(opt.vol)  error: $(ifelse(error == Inf, "-", error))"

        opt.iter += 1
    end

    open("$(replace(opt.filename, ".json" => "_output.json"))", "w") do io
        JSON.print(io, opt.output)
    end

    @info "================== Optimization finished =================="
    
    output_summary(opt)

end

function output_summary(opt::Optimizer)
    @info "File name: $(opt.filename)"
    @info "Final compliance: $(obj(opt.compliance))"
    @info "Final volume: $(opt.vol)"
    @info "Final error: $(error)"
    @info "Number of iterations: $(opt.iter)"
    @info "Number of elements: $(length(opt.x_k))"
    @info "Number of nodes: $(length(opt.compliance.base.structure.nodes))"
    @info "Mean move: $(length(mean(opt.move)))"
end

function angle(opt::Optimizer)
    forces = H(opt.compliance.base) * opt.compliance.base.eig_vecs[:, end]
    fx, fy = [f for f in forces if abs(f) > 0.0][1:2]

    return atand(fy, fx)
end
