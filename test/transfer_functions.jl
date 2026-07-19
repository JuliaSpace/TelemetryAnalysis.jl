## Description #############################################################################
#
# Tests integer telemetry transfer-function decoders.
#
############################################################################################

@testset "Integer decoders" begin
    @test tf_uint8(UInt8[0xAB]) === 0xAB
    @test tf_uint16(UInt8[0x34, 0x12]) === UInt16(0x1234)
    @test tf_uint32(UInt8[0x78, 0x56, 0x34, 0x12]) === UInt32(0x12345678)

    @test tf_uint64(UInt8[0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01]) ===
        UInt64(0x0123456789ABCDEF)

    decoders = ((tf_uint8, 1), (tf_uint16, 2), (tf_uint32, 4), (tf_uint64, 8))
    for (decoder, length_required) in decoders
        @test_throws ArgumentError decoder(zeros(UInt8, length_required - 1))
        leading = fill(0x01, length_required)
        @test decoder([leading; 0xFF]) == decoder(leading)
    end
end
