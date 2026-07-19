## Description #############################################################################
#
# Miscellaneous functions.
#
############################################################################################

export analyze_byte_array, byte_array_to_hex, byte_array_to_binary, checkbit

const _HEX_DIGITS = codeunits("0123456789ABCDEF")

"""
    analyze_byte_array(byte_array::AbstractVector{UInt8}; kwargs...)

Print a table containing binary, decimal, and hexadecimal representations of `byte_array`.
"""
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
    output = Base.StringVector(2 + 8length(byte_array))
    output[1] = UInt8('0')
    output[2] = UInt8('b')
    output_index = 3

    @inbounds for index in Iterators.reverse(eachindex(byte_array))
        byte = byte_array[index]
        for shift in 7:-1:0
            output[output_index] = UInt8('0') + ((byte >> shift) & 0x01)
            output_index += 1
        end
    end

    return String(output)
end

"""
    byte_array_to_hex(byte_array::AbstractVector{UInt8}) -> String

Convert the `byte_array` to a hexadecimal string.
"""
function byte_array_to_hex(byte_array::AbstractVector{UInt8})
    output = Base.StringVector(2 + 2length(byte_array))
    output[1] = UInt8('0')
    output[2] = UInt8('x')
    output_index = 3

    @inbounds for index in Iterators.reverse(eachindex(byte_array))
        byte = byte_array[index]
        output[output_index] = _HEX_DIGITS[Int(byte >> 4) + 1]
        output[output_index + 1] = _HEX_DIGITS[Int(byte & 0x0F) + 1]
        output_index += 2
    end

    return String(output)
end

"""
    checkbit(raw::T, bit::Integer) where T <: Integer -> Bool

Check if the `bit` in `raw` is set. The least significant bit is 1.
"""
function checkbit(raw::T, bit::Integer) where T<:Integer
    bit >= 1 || throw(ArgumentError("bit position must be at least 1; received $bit."))
    if isbitstype(T)
        width = 8sizeof(T)
        bit <= width || throw(ArgumentError(
            "bit position must not exceed $width for $T; received $bit."))
    end
    mask = one(raw) << (bit - 1)
    return (raw & mask) != zero(raw)
end
