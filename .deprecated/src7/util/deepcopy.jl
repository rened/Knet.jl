# deep copying between cpu/gpu
#
# I duplicated the code from base/deepcopy.jl to cpucopy and gpucopy:
#
# deepcopy(x)
#   deepcopy_internal(x,s)
#     _deepcopy_t(x,T,s)
#   deepcopy_internal(x::Array,s)
#     _deepcopy_array_t(x,T,s)
#
# cpucopy and gpucopy differ from deepcopy only in how Arrays,
# CudaArrays and other types based on them are handled.  New types can
# override deepcopy_internal, cpucopy_internal and gpucopy_internal.

using CUDArt
using Base: arrayset
VERSION < v"0.4-" && (nfields(a)=length(names(a)))

cpucopy(x) = cpucopy_internal(x, IdDict())

cpucopy_internal(x::Union{Symbol,LambdaStaticData,TopNode,GlobalRef,
                 DataType,Union,Task},
                 stackdict::IdDict) = x
cpucopy_internal(x::Tuple, stackdict::IdDict) =
    ntuple(i->cpucopy_internal(x[i], stackdict), length(x))
cpucopy_internal(x::Module, stackdict::IdDict) = error("cpucopy of Modules not supported")

function cpucopy_internal(x::Function, stackdict::IdDict)
    if isa(x.env, Union{MethodTable, Symbol}) || x.env === ()
        return x
    end
    invoke(cpucopy_internal, Tuple{Any, IdDict}, x, stackdict)
end

function cpucopy_internal(x, stackdict::IdDict)
    if haskey(stackdict, x)
        return stackdict[x]
    end
    _cpucopy_t(x, typeof(x), stackdict)
end

function _cpucopy_t(x, T::DataType, stackdict::IdDict)
    nf = nfields(T)
    (isbits(T) || nf == 0) && return x
    if T.mutable
        y = ccall(:jl_new_struct_uninit, Any, (Any,), T)
        stackdict[x] = y
        for i in 1:nf
            if isdefined(x,i)
                y.(i) = cpucopy_internal(x.(i), stackdict)
            end
        end
    else
        fields = Any[cpucopy_internal(x.(i), stackdict) for i in 1:nf]
        y = ccall(:jl_new_structv, Any, (Any, Ptr{Void}, UInt32),
                  T, pointer(fields), length(fields))
    end
    return y::T
end

function cpucopy_internal(x::Array, stackdict::IdDict)
    if haskey(stackdict, x)
        return stackdict[x]
    end
    _cpucopy_array_t(x, eltype(x), stackdict)
end

function _cpucopy_array_t(x, T, stackdict::IdDict)
    if isbits(T)
        return (stackdict[x]=copy(x))
    end
    dest = similar(x)
    stackdict[x] = dest
    for i=1:length(x)
        if isdefined(x,i)
            arrayset(dest, cpucopy_internal(x[i], stackdict), i)
        end
    end
    return dest
end

gpucopy(x) = gpucopy_internal(x, IdDict())

gpucopy_internal(x::Union{Symbol,LambdaStaticData,TopNode, # GlobalRef,
                            DataType,Union,Task},
                   stackdict::IdDict) = x
gpucopy_internal(x::Tuple, stackdict::IdDict) =
    ntuple(i->gpucopy_internal(x[i], stackdict), length(x))
gpucopy_internal(x::Module, stackdict::IdDict) = error("gpucopy of Modules not supported")

function gpucopy_internal(x::Function, stackdict::IdDict)
    if isa(x.env, Union{MethodTable, Symbol}) || x.env === ()
        return x
    end
    invoke(gpucopy_internal, Tuple{Any, IdDict}, x, stackdict)
end

function gpucopy_internal(x, stackdict::IdDict)
    if haskey(stackdict, x)
        return stackdict[x]
    end
    _gpucopy_t(x, typeof(x), stackdict)
end

function _gpucopy_t(x, T::DataType, stackdict::IdDict)
    nf = nfields(T)
    (isbits(T) || nf == 0) && return x
    if T.mutable
        y = ccall(:jl_new_struct_uninit, Any, (Any,), T)
        stackdict[x] = y
        for i in 1:nf
            if isdefined(x,i)
                y.(i) = gpucopy_internal(x.(i), stackdict)
            end
        end
    else
        fields = Any[gpucopy_internal(x.(i), stackdict) for i in 1:nf]
        y = ccall(:jl_new_structv, Any, (Any, Ptr{Void}, UInt32),
                  T, pointer(fields), length(fields))
    end
    return y::T
end

function gpucopy_internal(x::Array, stackdict::IdDict)
    if haskey(stackdict, x)
        return stackdict[x]
    end
    _gpucopy_array_t(x, eltype(x), stackdict)
end

function _gpucopy_array_t(x, T, stackdict::IdDict)
    if isbits(T)
        return (stackdict[x]=copy(x))
    end
    dest = similar(x)
    stackdict[x] = dest
    for i=1:length(x)
        if isdefined(x,i)
            arrayset(dest, gpucopy_internal(x[i], stackdict), i)
        end
    end
    return dest
end