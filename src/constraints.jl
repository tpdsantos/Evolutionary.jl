
export @addconstraints, @addconstr, convert_constr, constr

const constr = Dict{Symbol, Any}()

####################################################################

macro addconstraints(constraints...)
    strvec = Vector{String}(undef, length(constraints))
    for (i,cmd) in enumerate(constraints)
        strvec[i] = string(cmd)
    end
    str = string("!(",strvec[1],")")
    for j in strvec[2:end]
        str *= string(" || !(",j,")")
    end

    constr[:constr] = str

    return nothing
end

####################################################################

function convert_constr(igene ::Integer, gene ::FloatGene)
    for (i,name) in enumerate(gene.name)
        str = "chrom[$igene].value[$i]"
        constr[:constr] = replace(constr[:constr],name=>str)
    end
    return nothing
end

function convert_constr(chrom ::Individual)
    for (igene, gene) in enumerate(chrom)
        convert_constr(igene, gene)
    end
    return nothing
end

####################################################################

macro addconstr(parallel ::Bool)
    constraint = quote end
    if haskey(constr, :constr)
        constraint = Meta.parse(constr[:constr])
    end
    ex_serial = quote
        function mut_with_constr(chrom ::Individual)
            while $(constraint)
                @info("Constraint violated, retrying...")
                for gene in chrom
                    mutate(gene)
                    if !isbound(gene)
                        mutate(gene)
                    end
                end
            end
        end
    end
    ex_parallel = quote
        @everywhere function mut_with_constr(chrom ::Individual)
            while $(constraint)
                @info("Constraint violated, retrying...")
                for gene in chrom
                    mutate(gene)
                    if !isbound(gene)
                        mutate(gene)
                    end
                end
            end
        end
    end
    if parallel
        return esc(ex_parallel)
    else
        return esc(ex_serial)
    end
end
