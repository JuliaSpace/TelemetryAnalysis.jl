## Description #############################################################################
#
# Miscellaneous functions.
#
############################################################################################

export analyze_byte_array, byte_array_to_hex, byte_array_to_binary, checkbit

function analyze_byte_array(
    byte_array::AbstractVector{UInt8};
    order::Symbol = :descending,
    binarysep::Bool = true
)
    num_bytes = length(byte_array)

    column_labels = ["#$i" for i in 1:num_bytes]

    if order == :descending
        column_labels = column_labels |> reverse
    end

    data = Matrix{String}(undef, 3, num_bytes)

    for i = 1:num_bytes
        byte = byte_array[i - 1 + begin]

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

    table_format = TextTableFormat(
        ;
        @text__no_horizontal_lines,
        @text__no_vertical_lines,
        horizontal_line_after_column_labels  = true,
        vertical_line_after_row_label_column = true
    )

    pretty_table(
        data;
        column_labels  = column_labels,
        row_labels     = ["Binary", "Decimal", "Hexadecimal"],
        stubhead_label = "Byte #",
        table_format   = table_format
    )
end

"""
    byte_array_to_binary(byte_array::AbstractVector{UInt8})

Convert the `byte_array` to a binary string.
"""
function byte_array_to_binary(byte_array::AbstractVector{UInt8})
    hex_buf = IOBuffer(sizehint = 2length(byte_array) + 2)
    write(hex_buf, "0b")

    for i in reverse(eachindex(byte_array))
        write(hex_buf, string(byte_array[i], base = 2, pad = 8) |> uppercase)
    end

    return String(take!(hex_buf))
end

"""
    byte_array_to_hex(byte_array::AbstractVector{UInt8}) -> String

Convert the `byte_array` to an hexadecimal string.
"""
function byte_array_to_hex(byte_array::AbstractVector{UInt8})
    hex_buf = IOBuffer(sizehint = 2length(byte_array) + 2)
    write(hex_buf, "0x")

    for i in reverse(eachindex(byte_array))
        write(hex_buf, string(byte_array[i], base = 16, pad = 2) |> uppercase)
    end

    return String(take!(hex_buf))
end

"""
    checkbit(raw::T, bit::Integer) where T <: Integer -> Bool

Check if the `bit` in `raw` is set. The least significant bit is 1.
"""
function checkbit(raw::T, bit::Integer) where T<:Integer
    return (raw & (T(1) << (bit - 1))) > 0
end
