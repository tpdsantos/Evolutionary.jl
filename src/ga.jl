##### ga.jl #####

# In this file you will find the Genetic Algorithm.

####################################################################

export ga

mutable struct OptimResults
    N       ::Int64
    bestFit ::Float64
    bestInd ::Individual
    time    ::Float64
    threads ::Int64
    iter    ::Int64
    
end

####################################################################

"""
    ga( objfun        ::Function                            ,
        population    ::Vector{Individual}                  ;
        crossoverRate ::Float64                   = 0.5     ,
        mutationRate  ::Float64                   = 0.5     ,
        ϵ             ::Bool                      = true    ,
        iterations    ::Integer                   = 100     ,
        tol           ::Real                      = 0.0     ,
        parallel      ::Bool                      = false   ,
        piping        ::Union{Nothing,GAExternal} = nothing ,
        nworkers      ::Integer                   = 1       ,
        output        ::AbstractString            = ""      ,
        showprint     ::Bool                      = true    ,
        isbackup      ::Bool                      = true    ,
        backuptime    ::Float64                   = 1.0     )

Runs the Genetic Algorithm using the objective function `objfun` and the initial population `population`. `objfun` is the function to MINIMIZE. The table below shows how the optional arguments behave:

| Optional Argument | Behaviour |
|-------------------|-----------|
| crossoverRate     | rate in which the population mates |
| mutationRate | rate in which a gene mutates |
| ϵ | set elitism to true or false |
| iterations | number of iterations to be run |
| tol | objective function tolerance |
| parallel | sets parallelization to true or false |
| piping | if piping is different from `nothing`, uses external program |
| nworkers | number of threads to be used. Only works if parallel is set to true |
| output | writes optimization output to a file |
| showprint | set screen output to true or false |
| isbackup | sets backup to true or false |
| backuptime | backup interval in seconds|
"""
function ga( objfun        ::Function                            ,
             population    ::Vector{Individual}                  ;
             crossoverRate ::Float64                   = 0.5     ,
             mutationRate  ::Float64                   = 0.5     ,
             ϵ             ::Bool                      = true    ,
             iterations    ::Integer                   = 100     ,
             tol           ::Real                      = 0.0     ,
             parallel      ::Bool                      = false   ,
             piping        ::Union{Nothing,GAExternal} = nothing ,
             nworkers      ::Integer                   = 1       ,
             output        ::AbstractString            = ""      ,
             showprint     ::Bool                      = true    ,
             isbackup      ::Bool                      = true    ,
             backuptime    ::Union{Integer,Float64}    = 1       )

    # Initialize population
    N = length(population)
    fitness = Vector{Float64}(undef, N)

    # check if piping is used
    if piping == nothing
        func = objfun
    else
        func(x) = objfun(x, piping)
    end

    # save optional arguments in a dictionary
    # to pass to one of the generation functions
    pars = Dict{Symbol, Any}()
    pars[:crossoverRate] = crossoverRate
    pars[:mutationRate ] = mutationRate
    pars[:ϵ            ] = ϵ
    pars[:iterations   ] = iterations
    pars[:tol          ] = tol
    pars[:backuptime   ] = isbackup ? backuptime : Inf

    # choose run method depending if it's parallel
    # or serial processing
    if parallel
        if piping == nothing
            works = workers()[1:nworkers]
        else
            works = piping.avail_workers
        end
        if isbackup
            for w in works
                if !remotecall_fetch(isdir, w, "backup-files")
                    remotecall_fetch(mkdir, w, "backup-files")
                    println("backup folder created")
                end
            end
        end

        # create distributed arrays for parallel processing
        population = distribute(population, procs=works)
        fitness    = distribute(   fitness, procs=works)
       
        # run generations
        elapsed_time = @elapsed begin
            spmd(generations_parallel, func,
                 population, fitness, pars;
                 pids=works)
        end
    else
        # run generations
        elapsed_time = @elapsed begin
            generations(func, population, N, fitness, pars)
        end
    end

    bestFitness, bestIndividual = findmin(fitness)

    # result presentation
    data_presentation( population[bestIndividual], N, nworkers, iterations, bestFitness,
                       elapsed_time, showprint, output )
    
    return OptimResults(N, bestFitness, population[bestIndividual], elapsed_time,
                        nworkers, iterations)
end

####################################################################

function generations( objfun     ::Function           ,
                      population ::Vector{Individual} ,
                      N          ::Integer            ,
                      fitness    ::Vector{Float64}    ,
                      pars       ::Dict{Symbol,Any}   )
    
    # Variable initialization
    offspring      = Vector{Individual}(undef,   N)
    full_pop       = Vector{Individual}(undef, 2*N)
    full_fit       = Vector{Float64   }(undef, 2*N)

    fitness = objfun.(population)
    full_fit[1:N] = copy(fitness)
    full_pop[1:N] = deepcopy(population)
    
    # Elitism
    # When true, always picks N best individuals from the full population
    # (parents+offspring), which is size 2*N.
    # When false, only uses offspring
    function elitism_true()
        @inbounds begin
            full_pop[N+1:2*N] = offspring
            full_fit[N+1:2*N] = objfun.(offspring)
            fitidx            = sortperm(full_fit)
        end
        @inbounds begin
            population = full_pop[fitidx[1:N]]
               fitness = full_fit[fitidx[1:N]]
        end
        @inbounds begin
              full_fit[1:N] = copy(fitness)
              full_pop[1:N] = deepcopy(population)
        end
        return nothing
    end
    function elitism_false()
        @inbounds begin
            population = deepcopy(offspring)
               fitness = objfun.(population)
        end
        return nothing
    end

    if pars[:ϵ]
        elitism = elitism_true
    else
        elitism = elitism_false
    end
    
    t_ref = time()
    # Generate and evaluate offspring
    for iter in 1:pars[:iterations]

        # backup process
        dt = time() - t_ref
        if dt > pars[:backuptime]
            backup(iter, population)
            t_ref = time()
        end
        
        # Select offspring
        selected = selection(fitness, N)
        
        # Perform mating
        offidx = randperm(N)
        for i in 1:2:N
            j = (i == N) ? i-1 : i+1
            if rand() < pars[:crossoverRate]
                @inbounds begin
                    offspring[i], offspring[j] =
                        crossover( population[selected[offidx[i]]] ,
                                   population[selected[offidx[j]]] )
                end
            else
                @inbounds begin
                    offspring[i], offspring[j] =
                        population[selected[i]], population[selected[j]]
                end
            end
        end
        
        # Perform mutation
        for i in 1:N
            @inbounds mutate(offspring[i], pars[:mutationRate])
        end
        
        elitism()

    end

    return nothing
end

####################################################################

function generations_parallel( objfun ::Function                                ,
                               popul  ::DArray{Individual,1,Vector{Individual}} ,
                               fit    ::DArray{Float64,1,Vector{Float64}}       ,
                               pars   ::Dict{Symbol,Any}                        )
    # Variable initialization
    N              = length(popul[:L])
    offspring      = Vector{Individual}(undef,  N)
    full_pop       = Vector{Individual}(undef, 2N)
    full_fit       = Vector{Float64   }(undef, 2N)

     fit[:L][1:N] = objfun.(popul[:L])
    full_fit[1:N] = copy(fit[:L])
    full_pop[1:N] = deepcopy(popul[:L])
    
    # Elitism
    # When true, always picks N best individuals from the full population
    # (parents+offspring), which is size 2N.
    # When false, only uses offspring
    function elitism_true()
        @inbounds begin
            full_pop[N+1:2N] = offspring
            full_fit[N+1:2N] = objfun.(offspring)
            fitidx = sortperm(full_fit)
        end
        @inbounds begin
            popul[:L] = full_pop[fitidx[1:N]]
              fit[:L] = full_fit[fitidx[1:N]]
        end
        @inbounds begin
            full_fit[1:N] = copy(fit[:L])
            full_pop[1:N] = deepcopy(popul[:L])
        end
        return nothing
    end
    function elitism_false()
        @inbounds begin
            popul[:L][1:N] = offspring[1:N]
              fit[:L][1:N] = objfun.(popul[:L][1:N])
        end
        return nothing
    end

    if pars[:ϵ]
        elitism = elitism_true
    else
        elitism = elitism_false
    end

    t_ref = time()
    iter_backup = 0
    iter_cter = 0
    # Generate and evaluate offspring
    for iter in 1:pars[:iterations]
        iter_cter = iter
        # backup process
        if typeof(pars[:backuptime]) <: Real
            dt = time() - t_ref
            if dt > pars[:backuptime]
                file = "Backup_GA_worker$(myid())"
                backup(iter, pars[:iterations], popul[:L], file)
                t_ref = time()
            end
        elseif typeof(pars[:backuptime]) <: Integer
            dt = iter - iter_backup
            if dt > pars[:backuptime]
                file = "Backup_GA_worker$(myid())"
                backup(iter, pars[:iterations], popul[:L], file)
                iter_backup = iter
            end
        else
            @error("Type of backuptime not recognized, backup unsuccessful")
        end

        # Select offspring
        selected = selection(fit[:L], N)
        
        # Perform mating
        offidx = randperm(N)
        for i in 1:2:N
            j = (i == N) ? i-1 : i+1
            if rand() < pars[:crossoverRate]
                @inbounds begin
                    offspring[i], offspring[j] =
                        crossover( popul[:L][selected[offidx[i]]] ,
                                   popul[:L][selected[offidx[j]]] )
                end
            else
                @inbounds begin
                    offspring[i], offspring[j] =
                        deepcopy(popul[:L][selected[i]]),
                        deepcopy(popul[:L][selected[j]])
                end
            end
        end
        
        # Perform mutation
        for i in 1:N
             @inbounds mutate(offspring[i], pars[:mutationRate])
        end
        
        elitism()
        
    end
    
    @info("Worker $(myid()-1) finished after $(iter_cter) iterations")
    return nothing
end
    
####################################################################

function data_presentation( individual   ::Individual ,
                            popsize      ::Integer    ,
                            nworkers     ::Integer    ,
                            generations  ::Integer    ,
                            bestFitness  ::Float64    ,
                            elapsed_time ::Float64    ,
                            showprint    ::Bool       ,
                            output       ::String     )

    optim_time  = round(elapsed_time, digits=5)
    bestFitness = round(bestFitness, digits=15)
    
    params = Vector{AbstractString}(undef, 0)
    values = Vector{Real}(undef, 0)
    for gene in individual
        if isa(gene, FloatGene)
            for (i,j) in enumerate(gene.value)
                push!(params, gene.name[i])
                push!(values, j)
            end
        elseif isa(gene, IntegerGene)
            push!(params, gene.name)
            push!(values, bin(gene))
        elseif isa(gene, BinaryGene)
            push!(params, gene.name)
            push!(values, gene.value)
        else
            nothing
        end
    end

    val_maxsize, str_vals = present_numbers(values, 15)
    name_maxsize = present_names(params)
    if val_maxsize < length("value")
        val_maxsize = length("value")
    end
    if name_maxsize < length("parameter")
        name_maxsize = length("parameter")
    end
    i_str = "| %-$(name_maxsize)s | %-$(val_maxsize)s |\n"
    table = @eval @sprintf($i_str, "parameter", "value")
    iv = "|"
    for i in 1:name_maxsize+2
        iv *= "-"
    end
    iv *= "|"
    for i in 1:val_maxsize+2
        iv *= "-"
    end
    table *= iv * "|\n"
    for (i,j) in enumerate(params)
        s_val = str_vals[i]
        table *= @eval @sprintf($i_str, $j, $s_val)
    end

    if showprint
        printstyled("\nRESULTS :\n", color=:bold)
        println("population size       = $popsize"           )
        println("number of threads     = $nworkers"          )
        println("number of generations = $generations"       )
        println("best Fitness          = $bestFitness"       )
        println("Run time              = $optim_time seconds")
        println("")
        printstyled("GENES OF BEST INDIVIDUAL :\n", color=:bold)
        println(table)
        println("")
        printstyled("OPTIMIZATION FINISHED SUCCESSFULLY\n"  , color=:bold)
    end

    if output != ""
        open(output, "w") do f
            write(f, "Result File of Genetic Algorithm, $(now())\n\n")
            write(f, "RESULTS :\n")
            write(f, string("population size       = ", popsize    ,        "\n"))
            write(f, string("number of threads     = ", nworkers   ,        "\n"))
            write(f, string("number of generations = ", generations,        "\n"))
            write(f, string("best Fitness          = ", bestFitness,        "\n"))
            write(f, string("Run time              = ", optim_time , "seconds\n"))
            write(f, "\n")
            write(f, "GENES OF BEST INDIVIDUAL :\n")
            write(f, table)
            write(f, "\n")
            write(f, "OPTIMIZATION FINISHED SUCCESSFULLY\n")
        end
    end

    return nothing
end

####################################################################

function present_numbers(values ::Vector{<:Real}, round_digits ::Int64)
    for (i,j) in enumerate(values)
        if isa(j, Float64)
            values[i] = round(j, digits=round_digits)
        end
    end
    
    str_vals = [string(j) for j in values]
    for (i,j) in enumerate(str_vals)
        if j == "true"
            str_vals[i] = "1"
        elseif j == "false"
            str_vals[i] = "0"
        else
            nothing
        end
    end
    
     left_dot = Vector{AbstractString}(undef, length(values))
    right_dot = Vector{AbstractString}(undef, length(values))
    for (i,j) in enumerate(str_vals)
        j_spl = split(j, ".")
        if length(j_spl) == 2
            left  = j_spl[1]
            right = j_spl[2]
        else
            left  = j_spl[1]
            right = ""
        end
         left_dot[i] = left
        right_dot[i] = right
    end

    left_maxsize = 0
    for i in left_dot
        l = length(i)
        if l > left_maxsize
            left_maxsize = l
        end
    end

    right_maxsize = 0
    for i in right_dot
        l = length(i)
        if l > right_maxsize
            right_maxsize = l
        end
    end
    
    for (i,j) in enumerate(left_dot)
        ind = left_maxsize - length(j)
        str = ""
        if ind > 0
            for k in 1:ind
                str *= " "
            end
        end
        left_dot[i] = str * j
    end

    for i in 1:length(str_vals)
        if right_dot[i] == ""
            str_vals[i] = left_dot[i]
            if right_maxsize == 0
                iv = right_maxsize
            else
                iv = right_maxsize+1
            end
            for i in 1:iv
                str_vals[i] *= " "
            end
        else
            str_vals[i] = string(left_dot[i],".",right_dot[i])
        end
    end

    str_maxsize = 0
    for i in str_vals
        l = length(i)
        if l > str_maxsize
            str_maxsize = l
        end
    end

    return str_maxsize, str_vals
end

####################################################################

function present_names(names ::Vector{AbstractString})
    name_maxsize = 0
    for i in names
        l = length(i)
        if l > name_maxsize
            name_maxsize = l
        end
    end
    return name_maxsize
end
