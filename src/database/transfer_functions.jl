## Description #############################################################################
#
# Some common transfer functions.
#
############################################################################################

export tf_uint8, tf_uint16, tf_uint32, tf_uint64, tf_nothing

"""
    tf_uint8(raw::AbstractVector{UInt8}) -> UInt8

Convert the raw telemetry into an `UInt8`.
"""
function tf_uint8(raw::AbstractVector{UInt8})
    return raw[begin]
end

"""
    tf_uint16(raw::AbstractVector{UInt8}) -> UInt16

Convert the raw telemetry into an `UInt16`.
"""
function tf_uint16(raw::AbstractVector{UInt8})
    return reinterpret(UInt16, Vec(raw[begin], raw[1 + begin]))
end

"""
    tf_uint32(raw::AbstractVector{UInt8}) -> UInt32

Convert the raw telemetry into an `UInt32`.
"""
function tf_uint32(raw::AbstractVector{UInt8})
    return reinterpret(
        UInt32,
        Vec(raw[begin], raw[1 + begin], raw[2 + begin], raw[3 + begin])
    )
end

"""
    tf_uint64(raw::AbstractVector{UInt8}) -> UInt64

Convert the raw telemetry into an `UInt64`.
"""
function tf_uint64(raw::AbstractVector{UInt8})
    return reinterpret(UInt64, Vec(
        raw[begin],
        raw[1 + begin],
        raw[2 + begin],
        raw[4 + begin],
        raw[5 + begin],
        raw[6 + begin],
        raw[7 + begin],
    ))
end

"""
    tf_nothing(raw::AbstractVector{UInt8}) -> Nothing

Dummy function that returns `nothing` and should be used for those variables that does not
have a transfer function.
"""
function tf_nothing(raw::AbstractVector{UInt8})
    return nothing
end
