## Description #############################################################################
#
# Tests byte-array formatting and bit validation utilities.
#
############################################################################################

@testset "Byte formatting" begin
    bytes = UInt8[0x01, 0xA2]
    @test byte_array_to_binary(bytes) == "0b1010001000000001"
    @test byte_array_to_hex(bytes) == "0xA201"
    @test byte_array_to_binary(UInt8[]) == "0b"
    @test byte_array_to_hex(UInt8[]) == "0x"
    @test byte_array_to_binary(UInt8[0x00, 0xFF, 0x05]) ==
        "0b000001011111111100000000"
    @test byte_array_to_hex(UInt8[0x00, 0x0A, 0xF0]) == "0xF00A00"
    @test ncodeunits(byte_array_to_binary(fill(0x00, 17))) == 2 + 8 * 17
    @test ncodeunits(byte_array_to_hex(fill(0x00, 17))) == 2 + 2 * 17
end

@testset "Bit validation" begin
    @test checkbit(UInt8(0x81), 1)
    @test checkbit(UInt8(0x81), 8)
    @test !checkbit(UInt8(0x00), 4)

    @test checkbit(Int8(-128), 8)
    @test checkbit(Int16(-32768), 16)
    @test !checkbit(Int8(1), 8)
    @test_throws ArgumentError checkbit(UInt8(1), 0)
    @test_throws ArgumentError checkbit(UInt8(1), 9)
    @test_throws ArgumentError checkbit(Int16(1), -1)
    @test_throws ArgumentError checkbit(Int16(1), 17)
    @test checkbit(big(1) << 199, 200)
    @test !checkbit(big(1), 200)
    @test checkbit(big(-1), 200)
    @test checkbit(-big(1) << 199, 200)
    @test_throws ArgumentError checkbit(big(1), 0)
end
