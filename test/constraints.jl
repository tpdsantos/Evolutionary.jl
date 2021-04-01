
using Evolutionary

nworks = 2

distributed_ga(localcpu=2)

gene1 = FloatGene([0.5,0.5], [0.2,0.2], ["A1","A2"], m = 20, lb = [0.0,0.0], ub = [1.0, 1.0])
gene2 = FloatGene([0.2,0.5], [0.2,0.2], ["B1","B2"], m = 20, lb = [0.0,0.0], ub = [1.0, 1.0])
chrom = AbstractGene[gene1, gene2]

npop = 10 * nworks
pop = Vector{Individual}(undef, npop)
for p in 1:npop
    pop[p] = copy(chrom)
end

@addconstraints(A1 - B1 > 0, B2 - A2 > 0)

@everywhere function objfun(chrom ::Individual)
    return abs( chrom[1].value[2] - 0.6 )
end

@everywhere Crossover(:SPX)
@everywhere Selection(:RWS)

opt = ga(objfun, pop,
         nworkers     = nworks ,
         parallel     = true   ,
         iterations   = 100    ,
         mutationRate = 0.8    )
