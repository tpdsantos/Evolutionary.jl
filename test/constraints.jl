
using Evolutionary

distributed_ga(localcpu=2)

gene1 = FloatGene([0.5,0.5], [0.5,0.5], ["A1","A2"], m = 5, lb = [0.,0.], ub = [1., 1.])
gene2 = FloatGene([0.5,0.5], [0.5,0.5], ["B1","B2"], m = 5, lb = [0.,0.], ub = [1., 1.])
global chrom = AbstractGene[gene1, gene2]

npop = 100
pop = Vector{Individual}(undef, npop)
for i in 1:npop
    pop[i] = copy(chrom)
end

@everywhere Selection(:RWS)
@everywhere Crossover(:SPX)

@addconstraints(chrom, A2 >= A1, B1 >= B2)

print("Creating objective function... ")
@everywhere function objfun(chrom ::Individual)
    return abs( chrom[1].value[1] - 2.1 )
end
println("DONE")

opt = ga(pop, objfun, parallel=true)

nothing
