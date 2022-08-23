# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Miscellaneous functions.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export analyze_raw_data

function analyze_raw_data(
    raw::AbstractVector{UInt8};
    order::Symbol = :descending,
    binarysep::Bool = true
)
    num_bytes = length(raw)

    header = ["#$i" for i in 1:num_bytes]

    if order == :descending
        header = header |> reverse
    end

    data = Matrix{String}(undef, 3, num_bytes)

    for i = 1:num_bytes
        byte = raw[begin + i - 1]

        hex_str = "0x" * (string(byte, base = 16, pad = 2) |> uppercase)
        dec_str = string(byte)

        if binarysep
            aux = string(byte, base =  2, pad = 8)

            # Since byte is `UInt8`, `aux` will always have 8 characters.
            bin_str = "0b" * aux[1:4] * "." * aux[5:8]

        else
            bin_str = "0b" * (string(byte, base =  2, pad = 8))
        end

        if order == :descending
            data[1, end - i + 1] = bin_str
            data[2, end - i + 1] = dec_str
            data[3, end - i + 1] = hex_str
        else
            data[1, i] = bin_str
            data[2, i] = dec_str
            data[3, i] = hex_str
        end
    end

    pretty_table(
        data;
        row_names = ["Binary", "Decimal", "Hexadecimal"],
        row_name_column_title = "Byte #",
        header = header,
        hlines = [:header],
        vlines = [1]
    )
end

#                              Private functions
# ==============================================================================

# Convert a raw telemetry to hexadecimal.
function _raw_to_hex(raw::AbstractVector{UInt8})
    hex_buf = IOBuffer(sizehint = 2length(raw) + 2)
    write(hex_buf, "0x")

    for i in reverse(eachindex(raw))
        write(hex_buf, string(raw[i], base = 16, pad = 2) |> uppercase)
    end

    return String(take!(hex_buf))
end

# Convert a raw telemetry to binary.
function _raw_to_binary(raw::AbstractVector{UInt8})
    hex_buf = IOBuffer(sizehint = 2length(raw) + 2)
    write(hex_buf, "0b")

    for i in reverse(eachindex(raw))
        write(hex_buf, string(raw[i], base = 2, pad = 8) |> uppercase)
    end

    return String(take!(hex_buf))
end
