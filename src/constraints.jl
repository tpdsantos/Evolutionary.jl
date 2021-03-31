
export @addconstraints

####################################################################

function constraints(chrom ::Individual, cmds...)
    strvec = Vector{AbstractString}(undef, length(cmds))
    for (i,cmd) in enumerate(cmds)
        strvec[i] = string(cmd)
    end
    for istr in 1:length(strvec)
        for (igene,gene) in enumerate(chrom)
            strvec[istr] = convert_constraint(igene, gene, strvec[istr])
        end
    end
    ifclause = string("!(",strvec[1],")")
    for i in 2:length(strvec)
        ifclause *= string(" || !(",strvec[i],")")
    end
    return Meta.parse(ifclause)
end

####################################################################

function convert_constraint(igene ::Integer, gene ::FloatGene, constraint ::AbstractString)
    for (iname,name) in enumerate(gene.name)
        if occursin(name, constraint)
            new_name = string("chrom[$igene].value[$iname]")
            constraint = replace(constraint, name => new_name)
        end
    end
    return constraint
end

####################################################################

macro addconstraints(chrom ::Symbol, cmds...)
    ex = eval( :( Evolutionary.constraints($chrom, $cmds...) ) )
    return esc( :(
        function Evolutionary.mutate(chrom ::Individual, rate ::Float64)
            for gene in chrom
                if rand() < rate
                    mutate(gene)
                end
                while !Evolutionary.isbound(gene)
                    mutate(gene)
                end
            end
            while $(ex)
                @info("constraint violated, retrying...")
                for gene in chrom
                    if rand() < rate
                        mutate(gene)
                    end
                    while !Evolutionary.isbound(gene)
                        mutate(gene)
                    end
                end 
            end
        end
    ) )
end
