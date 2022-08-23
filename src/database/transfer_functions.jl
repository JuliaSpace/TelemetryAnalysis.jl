# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Some common transfer functions.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export tf_uint8, tf_uint16, tf_uint32

"""
    tf_uint8(raw::AbstractVector{UInt8})

Convert the raw telemetry into an `UInt8`.
"""
function tf_uint8(raw::AbstractVector{UInt8})
    return raw[begin]
end

"""
    tf_uint16(raw::AbstractVector{UInt8})

Convert the raw telemetry into an `UInt16`.
"""
function tf_uint16(raw::AbstractVector{UInt8})
    return reinterpret(UInt16, raw[begin:begin+1]) |> first
end

"""
    tf_uint32(raw::AbstractVector{UInt8})

Convert the raw telemetry into an `UInt32`.
"""
function tf_uint32(raw::AbstractVector{UInt8})
    return reinterpret(UInt32, raw[begin:begin+1]) |> first
end
