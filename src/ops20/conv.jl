export conv4, deconv4, mat, pool, unpool
using NNlib: conv, DenseConvDims, maxpool, meanpool, PoolDims, ∇conv_data, ∇conv_filter, ∇maxpool, ∇meanpool
using LinearAlgebra: lmul!
using AutoGrad: AutoGrad, @primitive1


"""
    conv4(w, x; kwargs...)

Execute convolutions or cross-correlations using filters specified with `w` over tensor `x`.

If `w` has dimensions `(W1,W2,...,Cx,Cy)` and `x` has dimensions `(X1,X2,...,Cx,N)`, the
result `y` will have dimensions `(Y1,Y2,...,Cy,N)` where `Cx` is the number of input channels,
`Cy` is the number of output channels, `N` is the number of instances, and `Wi,Xi,Yi` are
spatial dimensions with `Yi` determined by:

    Yi = 1 + floor((Xi + 2*padding[i] - ((Wi-1)*dilation[i] + 1)) / stride[i])

`padding`, `stride` and `dilation` are keyword arguments that can be specified as a single
number (in which case they apply to all dimensions), or an array/tuple with entries for each
spatial dimension.

# Keywords

* `padding=0`: the number of extra zeros implicitly concatenated at the start and end of each dimension.
* `stride=1`: the number of elements to slide to reach the next filtering window.
* `dilation=1`: dilation factor for each dimension.
* `mode=0`: 0 for convolution and 1 for cross-correlation (which flips the filter).
* `alpha=1`: can be used to scale the result.
* `group=1`: can be used to perform grouped convolutions.

"""
function conv4(w, x; padding=0, stride=1, dilation=1, mode=0, alpha=1, group=1)
    @assert group == 1 "Grouped convolutions not yet implemented in NNlib, see https://github.com/JuliaGPU/CuArrays.jl/pull/523"
    N = ndims(x)
    stride = expand(Val(N-2), stride)
    padding = expand(Val(N-2), padding)
    dilation = expand(Val(N-2), dilation)
    cdims = DenseConvDims(x, w; stride = stride, padding = padding, dilation = dilation, flipkernel = (mode!=0))
    y = conv(x, w, cdims)
    alpha == 1 ? y : lmul!(alpha, y)
end

function conv4w(w,x,dy; padding=0, stride=1, dilation=1, mode=0, alpha=1, group=1)
    @assert group == 1 "Grouped convolutions not yet implemented in NNlib, see https://github.com/JuliaGPU/CuArrays.jl/pull/523"
    N = ndims(x)
    stride = expand(Val(N-2), stride)
    padding = expand(Val(N-2), padding)
    dilation = expand(Val(N-2), dilation)
    cdims = DenseConvDims(x, w; stride = stride, padding = padding, dilation = dilation, flipkernel = (mode!=0))
    dw = ∇conv_filter(x, dy, cdims)
    alpha == 1 ? dw : lmul!(alpha, dw)
end

function conv4x(w,x,dy; padding=0, stride=1, dilation=1, mode=0, alpha=1, group=1)
    @assert group == 1 "Grouped convolutions not yet implemented in NNlib, see https://github.com/JuliaGPU/CuArrays.jl/pull/523"
    N = ndims(x)
    stride = expand(Val(N-2), stride)
    padding = expand(Val(N-2), padding)
    dilation = expand(Val(N-2), dilation)
    cdims = DenseConvDims(x, w; stride = stride, padding = padding, dilation = dilation, flipkernel = (mode!=0))
    dx = ∇conv_data(dy, w, cdims)
    alpha == 1 ? dx : lmul!(alpha, dx)
end

@primitive1 conv4(w,x; o...),dy,y       conv4w(w,x,dy;o...)   conv4x(w,x,dy;o...)
@primitive1 conv4w(w,x,dy;o...),ddw,dw  nothing               conv4x(ddw,x,dy;o...)  conv4(ddw,x;o...)
@primitive1 conv4x(w,x,dy;o...),ddx,dx  conv4w(w,ddx,dy;o...) nothing                conv4(w,ddx;o...)


"""
    deconv4(w, x; kwargs...)

Simulate 4-D deconvolution by using _transposed convolution_ operation. Its forward pass is
equivalent to backward pass of a convolution (gradients with respect to input
tensor). Likewise, its backward pass (gradients with respect to input tensor) is equivalent to
forward pass of a convolution. Since it swaps forward and backward passes of convolution
operation, padding and stride options belong to output tensor. See [this
report](https://arxiv.org/abs/1603.07285) for further explanation.

If `w` has dimensions `(W1,W2,...,Cy,Cx)` and `x` has dimensions `(X1,X2,...,Cx,N)`, the
result `y=deconv4(w,x)` will have dimensions `(Y1,Y2,...,Cy,N)` where

    Yi = (Xi - 1)*stride[i] + ((Wi-1)*dilation[i] + 1) - 2*padding[i]

Here Cx is the number of x channels, Cy is the number of y channels, N is the number of
instances, and Wi,Xi,Yi are spatial dimensions. Padding and stride are keyword arguments that
can be specified as a single number (in which case they apply to all dimensions), or an
array/tuple with entries for each spatial dimension.

# Keywords

* `padding=0`: the number of extra zeros implicitly concatenated at the start and at the end of each dimension.
* `stride=1`: the number of elements to slide to reach the next filtering window.
* `mode=0`: 0 for convolution and 1 for cross-correlation.
* `alpha=1`: can be used to scale the result.
* `handle`: handle to a previously created cuDNN context. Defaults to a Knet allocated handle.
* `group=1`: can be used to perform grouped convolutions.

"""
function deconv4(w,y; o...)
    x = similar(y,dcdims(w,y;o...))
    return conv4x(w,x,y;o...)
end

@primitive1 deconv4(w,x;o...),dy  conv4w(w,dy,x;o...)  conv4(w,dy;o...)


"""
    pool(x; kwargs...)

Compute pooling of input values (i.e., the maximum or average of several adjacent values) to
produce an output with smaller height and/or width.

If `x` has dimensions `(X1,X2,...,Cx,N)`, the result `y` will have dimensions
`(Y1,Y2,...,Cx,N)` where

    Yi=1+floor((Xi+2*padding[i]-window[i])/stride[i])

Here `Cx` is the number of input channels, `N` is the number of instances, and `Xi,Yi` are
spatial dimensions.  `window`, `padding` and `stride` are keyword arguments that can be
specified as a single number (in which case they apply to all dimensions), or an array/tuple
with entries for each spatial dimension.

# Keywords:

* `window=2`: the pooling window size for each dimension.
* `padding=0`: the number of extra zeros implicitly concatenated at the start and at the end of each dimension.
* `stride=window`: the number of elements to slide to reach the next pooling window.
* `mode=0`: 0 for max, 1 for average including padded values, 2 for average excluding padded values, 3 for deterministic max.
* `maxpoolingNanOpt=1`: Nan numbers are not propagated if 0, they are propagated if 1.
* `alpha=1`: can be used to scale the result.

"""
function pool(x; window=2, padding=0, stride=window, mode=0, maxpoolingNanOpt=1, alpha=1)
    mode, maxpoolingNanOpt = checkpoolopts(x, window, padding, stride, mode, maxpoolingNanOpt, alpha)
    N = ndims(x)
    window = expand(Val(N-2), window)
    stride = expand(Val(N-2), stride)
    padding = expand(Val(N-2), padding)
    pdims = PoolDims(x, window; padding = padding, stride = stride)
    y = (mode == 0 ? maxpool(x, pdims) :
         mode == 1 ? meanpool(x, pdims) :
         mode == 2 ? error("Pool mode=2 not yet implemented in NNlib. See https://github.com/FluxML/NNlib.jl/issues/218") :
         mode == 3 ? maxpool(x, pdims) :
         error("mode=$mode is not supported for CPU pool."))
    alpha == 1 ? y : lmul!(alpha, y)
end

function poolx(x,y,dy; window=2, padding=0, stride=window, mode=0, maxpoolingNanOpt=1, alpha=1)
    mode, maxpoolingNanOpt = checkpoolopts(x, window, padding, stride, mode, maxpoolingNanOpt, alpha)
    if alpha != 1
        y = y ./ eltype(y)(alpha)
    end
    N = ndims(x)
    window = expand(Val(N-2), window)
    stride = expand(Val(N-2), stride)
    padding = expand(Val(N-2), padding)
    pdims = PoolDims(x, window; padding = padding, stride = stride)
    dx = (mode == 0 ? ∇maxpool(dy, y, x, pdims) :
          mode == 1 ? ∇meanpool(dy, y, x, pdims) :
          mode == 2 ? error("Pool mode=2 not yet implemented in NNlib. See https://github.com/FluxML/NNlib.jl/issues/218") :
          mode == 3 ? ∇maxpool(dy, y, x, pdims) :
          error("mode=$mode is not supported for CPU pool."))
    alpha == 1 ? dx : lmul!(alpha, dx)
end

@primitive1 pool(x;o...),dy,y  poolx(x,y,dy;o...)
@primitive1 poolx(x,y,dy;o...),ddx,dx  nothing  nothing  pool(ddx;o...)

function checkpoolopts(x, window, padding, stride, mode, maxpoolingNanOpt, alpha)
    @assert mode ∈ 0:3 "Bad pooling mode=$mode"
    if mode == 2
        @warn "Pool mode=2 not yet implemented in NNlib, using 1 instead. See https://github.com/FluxML/NNlib.jl/issues/218" maxlog=1
        mode = 1
    end
    @assert maxpoolingNanOpt ∈ (0,1) "Bad pooling maxpoolingNanOpt=$maxpoolingNanOpt"
    if maxpoolingNanOpt == 0
        @warn "Pool maxpoolingNanOpt=0 not yet implemented in NNlib, using 1 instead. See https://github.com/FluxML/NNlib.jl/issues/218" maxlog=1
        maxpoolingNanOpt = 1
    end
    return (mode, maxpoolingNanOpt)
end    


"""
    unpool(x; o...)

Perform the reverse of pooling: `x == pool(unpool(x;o...); o...)`
"""
function unpool(x; window=2, padding=0, stride=window, mode=0, maxpoolingNanOpt=1, alpha=1)
    if mode == 1 && x isa Array
        @warn "unpool(mode=1), which uses poolx(mode=2) is not supported on the CPU; performing unpool(mode=2) instead, see https://github.com/FluxML/NNlib.jl/issues/218" maxlog=1
    end
    w = prod(psize(window,x))
    y = similar(x,updims(x; window, padding, stride, mode, maxpoolingNanOpt, alpha))
    # pool0=>unpool1, pool1=>unpool2, pool2=>unpool1
    mode = (mode==0 ? 1 : mode==1 ? 2 : mode==2 ? 1 : mode==3 ? 1 : error("Unknown unpool mode $mode"))
    alpha = 1/alpha
    # Leave unpool as a non-primitive, it is just a poolx call
    poolx(y,x,x.*w; window, padding, stride, mode, maxpoolingNanOpt, alpha)
end



"""
    mat(x; dims = ndims(x) - 1)

Reshape `x` into a two-dimensional matrix by joining the first dims dimensions, i.e. 
`reshape(x, prod(size(x,i) for i in 1:dims), :)`

`dims=ndims(x)-1` (default) is typically used when turning the output of a 4-D convolution
result into a 2-D input for a fully connected layer.

`dims=1` is typically used when turning the 3-D output of an RNN layer into a 2-D input for
a fully connected layer.

`dims=0` will turn the input into a row vector, `dims=ndims(x)` will turn it into a column
vector.

"""
mat(x; dims::Int=ndims(x)-1)=reshape(x, (dims > 0 ? prod(size(x,i) for i in 1:dims) : 1), :)


## Dimension helpers:

# outputDim = 1 + ( inputDim + 2*pad - (((filterDim-1)*dilation)+1) )/convolutionStride;
# inputDim = (outputDim - 1) * convolutionStride + (((filterDim-1)*dilation)+1) - 2*pad
function dcdims(w,y; padding=0, stride=1, dilation=1, group=1, o...)
    N = ndims(y)
    @assert size(y,N-1) == size(w,N)
    ntuple(N) do i
        if i < N-1
            pi = (if isa(padding,Number); padding; else padding[i]; end)
            si = (if isa(stride,Number); stride; else stride[i]; end)
            di = (if isa(dilation,Number); dilation; else dilation[i]; end)
            si*(size(y,i)-1) + (((size(w,i)-1)*di)+1) - 2*pi
        elseif i == N-1
            size(w,N-1) * group
        else
            size(y,N)
        end
    end
end

# convert padding etc. size to an Int array of the right dimension
function psize(p, x)
    nd = ndims(x)-2
    if isa(p,Number)
        fill(Int(p),nd)
    elseif length(p)==nd
        collect(Int,p)
    else
        throw(DimensionMismatch("psize: $p $nd"))
    end
end

function updims(x; window=2, padding=0, stride=window, o...)
    window = psize(window,x)
    stride = psize(stride,x)
    padding = psize(padding,x)
    N = ndims(x)
    ntuple(N) do i
        if i < N-1
            (size(x,i)-1)*stride[i]+window[i]-2*padding[i]
        else
            size(x,i)
        end
    end
end

# convolution padding size that preserves the input size when filter size is odd and stride=1
padsize(w)=ntuple(i->div(size(w,i)-1,2), ndims(w)-2)

expand(N, i::Tuple) = i
expand(N, i::Integer) = ntuple(_ -> i, N)



# TODO: Grouped convolutions not yet implemented in NNlib, see https://github.com/JuliaGPU/CuArrays.jl/pull/523
# TODO: maxpoolingNanOpt not yet implemented in NNlib, see https://github.com/FluxML/NNlib.jl/issues/218
# TODO: Pool mode=2 not yet implemented in NNlib, see https://github.com/FluxML/NNlib.jl/issues/218
# TODO: unpool Does not work correctly for every window, padding, mode combination?
