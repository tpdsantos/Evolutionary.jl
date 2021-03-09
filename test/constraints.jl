
using Evolutionary

gene = FloatGene(2, "test")

macro test(cmds...)
   return esc( :( begin
                  for cmd in $cmds
                  if eval($cmd)
                  display(cmd)
                  else
                  display(cmd)
                  end
                  end
                  end
                  ) )
    return esc( :( $cmds ))
end

x = 3
y = 2

@time a = @test( x - y < 0, 1 - 2 < 0 )
