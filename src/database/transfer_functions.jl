## Description #############################################################################
#
# Some common transfer functions.
#
############################################################################################

export tf_uint8, tf_uint16, tf_uint32, tf_uint64, tf_nothing

"""
    tf_uint8(raw::AbstractVector{UInt8}) -> UInt8

Convert the raw telemetry into a `UInt8`. The first byte is the least significant byte.
"""
function tf_uint8(raw::AbstractVector{UInt8})
    length(raw) >= 1 || throw(ArgumentError("tf_uint8 requires at least 1 byte."))
    return @inbounds raw[begin]
end

"""
    tf_uint16(raw::AbstractVector{UInt8}) -> UInt16

Convert the raw telemetry into a `UInt16`. The first byte is the least significant byte.
"""
function tf_uint16(raw::AbstractVector{UInt8})
    length(raw) >= 2 || throw(ArgumentError("tf_uint16 requires at least 2 bytes."))
    first_index = firstindex(raw)
    return @inbounds UInt16(raw[first_index]) |
        (UInt16(raw[first_index + 1]) << 8)
end

"""
    tf_uint32(raw::AbstractVector{UInt8}) -> UInt32

Convert the raw telemetry into a `UInt32`. The first byte is the least significant byte.
"""
function tf_uint32(raw::AbstractVector{UInt8})
    length(raw) >= 4 || throw(ArgumentError("tf_uint32 requires at least 4 bytes."))
    first_index = firstindex(raw)
    value = zero(UInt32)
    @inbounds for offset in 0:3
        value |= UInt32(raw[first_index + offset]) << (8offset)
    end
    return value
end

"""
    tf_uint64(raw::AbstractVector{UInt8}) -> UInt64

Convert the raw telemetry into a `UInt64`. The first byte is the least significant byte.
"""
function tf_uint64(raw::AbstractVector{UInt8})
    length(raw) >= 8 || throw(ArgumentError("tf_uint64 requires at least 8 bytes."))
    first_index = firstindex(raw)
    value = zero(UInt64)
    @inbounds for offset in 0:7
        value |= UInt64(raw[first_index + offset]) << (8offset)
    end
    return value
end

"""
    tf_nothing(raw::AbstractVector{UInt8}) -> Nothing

Dummy function that returns `nothing` and should be used for variables without a
transfer function.
"""
function tf_nothing(raw::AbstractVector{UInt8})
    return nothing
end
