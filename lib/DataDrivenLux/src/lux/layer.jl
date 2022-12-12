"""
$(TYPEDEF)

A container for multiple [`DecisionNodes`](@ref). 
It accumulates all outputs of the nodes.

# Fields
$(FIELDS)
"""
struct FunctionLayer{skip, T, output_dimension} <:
       Lux.AbstractExplicitContainerLayer{(:nodes,)}
    nodes::T
end

mask_inverse(f::F, in_f) where F <: Function =  [InverseFunctions.inverse(f) != f_ for f_ in in_f]
mask_inverse(::typeof(+), in_f) = ones(Bool, length(in_f))
mask_inverse(::typeof(-), in_f) = ones(Bool, length(in_f))
mask_inverse(::Nothing, in_f) = ones(Bool, length(in_f))

function mask_parameters(arity, parameter_mask)
    arity <= 1 && return .! parameter_mask
    return ones(Bool, length(parameter_mask))
end

function FunctionLayer(in_dimension::Int, arities::Tuple, fs::Tuple; skip = false,
                       id_offset = 1, input_functions = (), parameter_mask = zeros(Bool, in_dimension),
                       kwargs...)

    nodes = map(eachindex(arities)) do i
        # We check if we have an inverse here
        local_input_mask = vcat(mask_inverse(fs[i], input_functions), mask_parameters(arities[i], parameter_mask))
        FunctionNode(fs[i],arities[i], in_dimension ,(id_offset, i), input_mask = local_input_mask, kwargs...)
    end

    output_dimension = length(arities)
    output_dimension += skip ? in_dimension : 0

    names = map(gensym ∘ string, fs)
    nodes = NamedTuple{names}(nodes)
    return FunctionLayer{skip, typeof(nodes), output_dimension}(nodes)
end

function (r::FunctionLayer)(x, ps, st)
    _apply_layer(r.nodes, x, ps, st)
end

function (r::FunctionLayer{true})(x, ps, st)
    y, st = _apply_layer(r.nodes, x, ps, st)
    vcat(y, x), st
end

Base.keys(m::FunctionLayer) = Base.keys(getfield(m, :nodes))

Base.getindex(c::FunctionLayer, i::Int) = c.nodes[i]

Base.length(c::FunctionLayer) = length(c.nodes)
Base.lastindex(c::FunctionLayer) = lastindex(c.nodes)
Base.firstindex(c::FunctionLayer) = firstindex(c.nodes)


function get_loglikelihood(r::FunctionLayer, ps, st)
    _get_layer_loglikelihood(r.nodes, ps, st)
end

@generated function _get_layer_loglikelihood(layers::NamedTuple{fields}, ps,
                                             st::NamedTuple{fields}) where {fields}
    N = length(fields)
    st_symbols = [gensym() for _ in 1:N]
    calls = [:($(st_symbols[i]) = get_loglikelihood(layers.$(fields[i]),
                                                    ps.$(fields[i]),
                                                    st.$(fields[i])))
             for i in 1:N]
    push!(calls, :(st = NamedTuple{$fields}((($(Tuple(st_symbols)...),)))))
    return Expr(:block, calls...)
end

@generated function _apply_layer(layers::NamedTuple{fields}, x, ps,
                                 st::NamedTuple{fields}) where {fields}
    N = length(fields)
    y_symbols = vcat([gensym() for _ in 1:N])
    st_symbols = [gensym() for _ in 1:N]
    calls = [:(($(y_symbols[i]), $(st_symbols[i])) = Lux.apply(layers.$(fields[i]),
                                                               x,
                                                               ps.$(fields[i]),
                                                               st.$(fields[i])))
             for i in 1:N]
    push!(calls, :(st = NamedTuple{$fields}((($(Tuple(st_symbols)...),)))))
    push!(calls, :(return vcat($(y_symbols...)), st))
    return Expr(:block, calls...)
end