abstract type AbstractAlgorithmCache end

using Base: dataids
struct SearchCache{ALG, N, M, P, B <: AbstractBasis} <: AbstractAlgorithmCache
    alg::ALG
    candidates::AbstractVector
    ages::AbstractVector{Int}
    sorting::AbstractVector{Int}
    keeps::AbstractVector{Bool}
    iterations::Int
    model::M
    p::P
    basis::B
    dataset::Dataset
end

function Base.show(io::IO, cache::SearchCache)
    print("Algorithm :")
    summary(io, cache.alg)
    println(io, "")
    for c in cache.candidates[cache.keeps]
        println(io, c)
    end
    return
end

function SearchCache(x::X where X <: AbstractDAGSRAlgorithm, basis::Basis, X::AbstractMatrix, Y::AbstractMatrix, 
        U::AbstractMatrix = Array{eltype(X)}(undef, 0, 0), t::AbstractVector = Array{eltype(X)}(undef, 0); kwargs...)

        @unpack n_layers, functions, arities, skip, rng, populationsize = x
        @unpack optimizer, optim_options, loss = x

        # Derive the model
        dataset = Dataset(X, Y, U, t)

        model = LayeredDAG(length(basis), size(Y, 1), n_layers, arities, functions, skip = skip)
        ps, st = Lux.setup(rng, model)
        
        pdists = get_parameter_distributions(basis)
        ptransform = get_parameter_transformation(basis)
        
        # Derive the candidates     
        candidates = map(1:populationsize) do i
            c = ConfigurationCache(model, ps, st, basis, dataset;
                pdist = pdists, transform_parameters = ptransform,
                kwargs...)
            c = optimize_configuration!(c, model, ps, dataset, basis, optimizer, optim_options)
        end
    
        keeps = zeros(Bool, populationsize)
        ages = zeros(Int, populationsize)
        sorting = sortperm(candidates, by = loss)
        
    
        return SearchCache{typeof(x), populationsize, typeof(model), typeof(ps), typeof(basis)}(x, candidates, ages, sorting,keeps, 0,model, ps, basis, dataset)
    end

function update_cache!(cache::SearchCache{<:AbstractDAGSRAlgorithm})
    @unpack candidates, p, model, alg, keeps, sorting, ages, iterations = cache
    @unpack keep, loss, distributed, optimizer, optim_options = alg
    @unpack basis, dataset = cache

    sortperm!(sorting, candidates, by = loss)

    keeps .= false

    permute!(candidates, sorting)

    if isa(keep, Int)
        keeps[1:keep] .= true
    else
        losses = map(loss, candidates)
        # TODO Maybe weight by age or loss here
        loss_quantile = quantile(losses, keep)
        keeps .= losses .<= loss_quantile
    end

    ages[keeps] .+= 1
    ages[.!keeps] .= 0

    # Update the parameters based on the current results
    p = update(p, model, alg, candidates, keeps, dataset, basis)

    # Update all 
    if distributed
        successes = pmap(1:length(keeps)) do i 
            if keeps[i]
                return true
            end
            try
                candidates[i] = resample!(candidates[i], model, p, dataset, basis, optimizer, optim_options)
                return true
            catch e
                @info "Failed to update $i on $(Distributed.myid())"
                return false
            end
        end
    else
        @inbounds for (i, keepidx) in enumerate(keeps)
            if !keepidx
                candidates[i] = resample!(candidates[i], model, p, dataset, basis, optimizer,
                                          optim_options)
            end
        end
    end 
        

    return
end

#function distributed_resample!(cache::SearchCache)
#
#    cache_channel = RemoteChannel(() -> Channel{SearchCache}(1), 1)
#    put!(cache_channel, deepcopy(cache))
#
#    done_channel = RemoteChannel(() -> Channel{Bool}(1), 1)
#    put!(done_channel, false)
#    
#    @unpack keeps = cache
#
#    pmap(1:length(keeps)) do i
#        @info Distributed.myid()
#        isdone = take!(done_channel)
#        put!(done_channel, isdone)
#        isdone && return
#
#        local_cache = take!(cache_channel)
#
#        @unpack keeps, candidates, dataset, basis, optimizer, optim_options, model, p = local_cache
#
#        put!(cache_channel, local_cache)
#        if !keeps[i]
#            candidates[i] = resample!(candidates[i], model, p, dataset, basis, optimizer, optim_options)
#        end
#        
#        local_cache.canddates[i] = candidates[i]
#
#        put!(cache_channel, local_cache)
#        candidates[i]
#    end 
#
#    # What we get out of the channel is an updated copy of our original hyperoptimizer.
#    # So now, back on the manager process, we take it out one last time and update
#    # the original hyperoptimizer.
#    updated_cache = take!(cache_channel)
#    close(cache_channel)
#
#            
#    # Do this last in case remaining runs are slow at starting so they can take the channel and stop
#    # properly without erroring (happens if accessing channel after closing)
#    close(done_channel)
#
#    updated_cache
#end