## Description #############################################################################
#
# Tests telemetry packet metadata behavior, display, allocation, and legacy fixtures.
#
############################################################################################

# Create escaped packets that use allocation-free default metadata storage.
function escaped_default_packets(count)
    return [packet() for _ in 1:count]
end

# Create escaped packets that each allocate an explicit mutable metadata dictionary.
function escaped_dictionary_packets(count)
    return [packet(; metadata = Dict{String, Any}()) for _ in 1:count]
end

@testset "Packet metadata and legacy fixture" begin
    first_packet = packet()
    second_packet = packet()
    @test first_packet.metadata === nothing
    @test second_packet.metadata === nothing
    @test !hasmetadata(first_packet)
    @test getmetadata(first_packet, "missing") === nothing
    @test getmetadata(first_packet, "missing", :fallback) === :fallback

    empty_metadata = Dict{String, Any}()
    mutable_packet = packet(; metadata = empty_metadata)
    @test mutable_packet.metadata === empty_metadata
    @test !hasmetadata(mutable_packet)
    mutable_packet.metadata["local"] = true
    @test hasmetadata(mutable_packet)
    @test getmetadata(mutable_packet, "local") === true

    replacement = Dict{String, Any}("mode" => "copied")
    replaced_packet = with_metadata(first_packet, replacement)
    @test replaced_packet !== first_packet
    @test replaced_packet.timestamp == first_packet.timestamp
    @test replaced_packet.data === first_packet.data
    @test replaced_packet.metadata == replacement
    @test replaced_packet.metadata !== replacement
    replacement["mode"] = "changed"
    @test getmetadata(replaced_packet, "mode") == "copied"
    @test with_metadata(replaced_packet, nothing).metadata === nothing

    compact = sprint(show, first_packet)
    detailed = sprint(show, MIME("text/plain"), first_packet)
    @test occursin("TelemetryPacket", compact)
    @test occursin("TelemetryPacket", detailed)
    @test first_packet.metadata === nothing

    # Warm both paths before comparing many escaped packet constructions.
    escaped_default_packets(2)
    escaped_dictionary_packets(2)
    default_allocations = @allocated escaped_default_packets(1_000)
    dictionary_allocations = @allocated escaped_dictionary_packets(1_000)
    @test default_allocations < dictionary_allocations
    @test fieldtype(typeof(first_packet), :metadata) ===
        Union{Nothing, Dict{String, Any}}

    minor = "$(VERSION.major).$(VERSION.minor)"
    fixture = joinpath(@__DIR__, "fixtures", "julia-$minor", "packets.ser.gz")
    fixture_required = minor in ("1.10", "1.12")
    if fixture_required || isfile(fixture)
        @test isfile(fixture)
        stream = GzipDecompressorStream(open(fixture))
        packets = try
            deserialize(stream)
        finally
            close(stream)
        end
        @test length(packets) == 2
        @test isempty(first(packets).metadata)
        @test last(packets).metadata ==
            Dict{String, Any}("mode" => "legacy", "id" => 7)
        @test hasmetadata(last(packets))
    end
end
