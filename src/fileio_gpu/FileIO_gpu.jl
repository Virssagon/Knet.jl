module FileIO_gpu

import FileIO # save, load
using JLD2: JLD2, JLDWriteSession, jldopen, isgroup, lookup_offset
using Knet.KnetArrays: KnetPtr, KnetArray, Cptr
using Knet.Ops20: RNN
using AutoGrad: Param
using CUDA: CUDA, functional, CuPtr

include("serialize.jl"); export cpucopy, gpucopy
include("jld.jl"); export save, load, @save, @load
include("serialization.jl"); # serialize, deserialize: note that these are Julia version specific
# include("jld2convert.jl")  # This does not work yet: https://github.com/JuliaIO/JLD2.jl/issues/40

end
