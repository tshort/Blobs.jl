"""
    child_size(::Type{T}, args...) where {T}

The number of bytes needed to allocate children of `T`, not including `self_size(T)`.

Defaults to 0.
"""
child_size(::Type{T}) where T = 0

"""
    init(blob::Blob{T}, args...) where T

Initialize `blob`.

Assumes that `blob` it at least `self_size(T) + child_size(T, args...)` bytes long.
"""
function init(blob::Blob{T}, args...) where T
    init(blob, Blob{Nothing}(blob + self_size(T)), args...)
end

"""
    init(blob::Blob{T}, free::Blob{Nothing}, args...)::Blob{Nothing} where T

Initialize `blob`, where `free` is the beginning of the remaining free space. Must return `free + child_size(T, args...)`.

The default implementation where `child_size(T) == 0` does nothing. Override this method to add custom initializers for your types.
"""
function init(blob::Blob{T}, free::Blob{Nothing}) where T
    @assert child_size(T) == 0 "Default init cannot be used for types for which child_size(T) != 0"
    # TODO should we zero memory?
    free
end

child_size(::Type{Blob{T}}, args...) where T = self_size(T) + child_size(T, args...)

function init(blob::Blob{Blob{T}}, free::Blob{Nothing}, args...) where T
    nested_blob = Blob{T}(free)
    blob[] = nested_blob
    init(nested_blob, free + self_size(T), args...)
end

child_size(::Type{BlobVector{T}}, length::Int64) where {T} = self_size(T) * length

function init(blob::Blob{BlobVector{T}}, free::Blob{Nothing}, length::Int64) where T
    blob.data[] = Blob{T}(free)
    blob.length[] = length
    free + child_size(BlobVector{T}, length)
end

child_size(::Type{BlobBitVector}, length::Int64) = self_size(UInt64) * Int64(ceil(length / 64))

function init(blob::Blob{BlobBitVector}, free::Blob{Nothing}, length::Int64)
    blob.data[] = Blob{UInt64}(free)
    blob.length[] = length
    free + child_size(BlobBitVector, length)
end

child_size(::Type{BlobString}, length::Int64) = length

function init(blob::Blob{BlobString}, free::Blob{Nothing}, length::Int64)
    blob.data[] = Blob{UInt8}(free)
    blob.len[] = length
    free + child_size(BlobString, length)
end

child_size(::Type{BlobString}, string::Union{String, BlobString}) = sizeof(string)

function init(blob::Blob{BlobString}, free::Blob{Nothing}, string::Union{String, BlobString})
    free = init(blob, free, sizeof(string))
    unsafe_copyto!(blob[], string)
    free
end

"""
    malloc(::Type{T}, args...)::Blob{T} where T

Allocate an uninitialized `Blob{T}`.
"""
function malloc(::Type{T}, args...)::Blob{T} where T
    size = self_size(T) + child_size(T, args...)
    Blob{T}(Libc.malloc(size), 0, size)
end

"""
    calloc(::Type{T}, args...)::Blob{T} where T

Allocate a zero-initialized `Blob{T}`.
"""
function calloc(::Type{T}, args...)::Blob{T} where T
    size = self_size(T) + child_size(T, args...)
    Blob{T}(Libc.calloc(1, size), 0, size)
end

"""
    malloc_and_init(::Type{T}, args...)::Blob{T} where T

Allocate and initialize a new `Blob{T}`.
"""
function malloc_and_init(::Type{T}, args...)::Blob{T} where T
    size = self_size(T) + child_size(T, args...)
    blob = Blob{T}(Libc.malloc(size), 0, size)
    used = init(blob, args...)
    @assert used - blob == size
    blob
end

"""
    free(blob::Blob)

Free the underlying allocation for `blob`.
"""
function free(blob::Blob)
    Libc.free(getfield(blob, :base))
end

function similar_immutable(x::Tx) where Tx
    isbits(x) && return Tx
    fn = fieldnames(Tx)
    ft = []
    for i in fn
        y = getfield(x, i)
        newtype = transform_type(y)
        isbitstype(newtype) || error("$i::$newtype is not a bitstype")
        push!(ft, newtype)
    end
    return NamedTuple{(fn...,), Tuple{ft...}}
end

transform_type(y) = typeof(y)
transform_type(y::String) = BlobString
transform_type(y::Vector{T}) where T = BlobVector{T}

"""
    malloc_and_init(x)

Allocate and initialize a new `Blob` using the contents of `x`.

If `x` contains mutable components, these are transformed using `transform_type` to (hopefully) an immutable type. 
"""
function malloc_and_init(x)
    T = similar_immutable(x)
    fn = fieldnames(typeof(x))
    size = sum(sizeof(getfield(x, i)) + extra_size(T.parameters[2].parameters[i]) for i in 1:length(fn))
    @show ptr = Libc.malloc(size)
    blob = Blob{T}(ptr, 0, size)
    @show used = init(blob)
    @show size
    for fn in fieldnames(typeof(x))
        @show fn
        @show used = init_value(getproperty(blob, fn), used, getproperty(x, fn))
    end
    blob
end

function init_value(x, free, val)
    x[] = val
    return free
end
# init_value(x::Blob{BlobString}, free, val::Union{String, BlobString}) = unsafe_copyto!(x[], val)
function init_value(blob::Blob{BlobVector{T}}, free::Blob{Nothing}, val::Vector{T}) where T
    sz = sizeof(val)
    blob.data[] = Blob{T}(free)
    blob.length[] = length(val)
    unsafe_copyto!(Ptr{T}(pointer(free)), pointer(val), length(val))
    @show Ptr{T}(pointer(free))
    @show pointer(val)
    free + sz
end

extra_size(x) = 0
extra_size(::Type{BlobVector{T}}) where T = sizeof(Int) * 2

