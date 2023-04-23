struct BlobBit
    data::Blob{UInt}
    mask::UInt
end

@inline Base.@propagate_inbounds function Base.getindex(blob::BlobBit)::Bool
    (blob.data[] & blob.mask) != 0
end

@inline Base.@propagate_inbounds function Base.setindex!(blob::BlobBit, v::Bool)::Bool
    c = blob.data[]
    c = ifelse(v, c | blob.mask, c & ~blob.mask)
    blob.data[] = c
    v
end

"A fixed-length bit vector whose data is stored in a Blob."
struct BlobBitVector <: AbstractArray{Bool, 1}
    data::Blob{UInt}
    length::Int
end

Base.@propagate_inbounds function get_address(blob::BlobBitVector, i::Int)::BlobBit
    @boundscheck begin
        (i < 1 || i > blob.length) && throw(BoundsError(blob, i))
    end
    i1, i2 = Base.get_chunks_id(i)
    BlobBit(blob.data + (i1-1)*self_size(UInt), UInt(1) << i2)
end

# blob interface

function Base.size(blob::Blob{BlobBitVector})
    (blob.length[],)
end

function Base.IndexStyle(_::Type{Blob{BlobBitVector}})
    Base.IndexLinear()
end

@inline Base.@propagate_inbounds function Base.getindex(blob::Blob{BlobBitVector}, i::Int)::BlobBit
    get_address(blob[], i)
end

function unsafe_resize!(blob::BlobBitVector, length::Int)
    blob.length[] = length
end

# array interface

function Base.size(blob::BlobBitVector)
    (blob.length,)
end

function Base.IndexStyle(_::Type{BlobBitVector})
    Base.IndexLinear()
end

@inline Base.@propagate_inbounds function Base.getindex(blob::BlobBitVector, i::Int)::Bool
    get_address(blob, i)[]
end

@inline Base.@propagate_inbounds function Base.setindex!(blob::BlobBitVector, v::Bool, i::Int)::Bool
    get_address(blob, i)[] = v
end

@inline function Base.findprevnot(blob::BlobBitVector, start::Int)::Union{Nothing,Int}
    start > length(blob) && throw(BoundsError(blob, start))
    # TODO(tjgreen) placeholder slow implementation; should adapt optimized BitVector code
    @inbounds while start > 0 && blob[start]
        start -= 1
    end
    start > 0 ? start : nothing
end

@inline function Base.findnextnot(blob::BlobBitVector, start::Int)::Union{Nothing,Int}
    start > 0 || throw(BoundsError(blob, start))
    # TODO(tjgreen) placeholder slow implementation; should adapt optimized BitVector code
    @inbounds while start <= length(blob) && blob[start]
        start += 1
    end
    start <= length(blob) ? start : nothing
end

@inline function Base.findnext(blob::BlobBitVector, start::Int)::Union{Nothing,Int}
    start > 0 || throw(BoundsError(blob, start))
    # TODO(tjgreen) placeholder slow implementation; should adapt optimized BitVector code
    @inbounds while start <= length(blob) && !blob[start]
        start += 1
    end
    start <= length(blob) ? start : nothing
end
