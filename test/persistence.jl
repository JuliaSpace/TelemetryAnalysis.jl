## Description #############################################################################
#
# Tests compressed telemetry serialization, loading, replacement, errors, and cleanup.
#
############################################################################################

"""
    InjectedLoadFailure

Marker serialized to inject a named-key deserialization failure.

# Fields

This marker has no fields.
"""
struct InjectedLoadFailure end

"""
    InjectedPlainKeyLoadFailure

Marker serialized to inject a plain-key deserialization failure.

# Fields

This marker has no fields.
"""
struct InjectedPlainKeyLoadFailure end

"""
    InjectedSaveFailure

Marker stored in packet metadata to inject a serialization failure.

# Fields

This marker has no fields.
"""
struct InjectedSaveFailure end

const INJECTED_LOAD_STREAM = Ref{Any}()
const INJECTED_PLAIN_KEY_LOAD_STREAM = Ref{Any}()
const INJECTED_SAVE_STREAM = Ref{Any}()

# Capture the load stream and inject a named-key failure to test propagation and cleanup.
function Serialization.deserialize(
    serializer::Serialization.AbstractSerializer,
    ::Type{InjectedLoadFailure},
)
    INJECTED_LOAD_STREAM[] = serializer.io
    throw(KeyError((; name = "InjectedLoadFailure")))
end

# Capture the load stream and inject a plain-key failure that has no `name` property.
function Serialization.deserialize(
    serializer::Serialization.AbstractSerializer,
    ::Type{InjectedPlainKeyLoadFailure},
)
    INJECTED_PLAIN_KEY_LOAD_STREAM[] = serializer.io
    throw(KeyError(:plain_key))
end

# Capture the save stream and fail serialization to test atomic preservation and cleanup.
function Serialization.serialize(
    serializer::Serialization.AbstractSerializer,
    ::InjectedSaveFailure,
)
    INJECTED_SAVE_STREAM[] = serializer.io
    error("injected serialization failure")
end

@testset "Persistence" begin
    mktempdir() do directory
        timestamp = DateTime(2024, 2, 3, 4, 5, 6)
        packets = [
            packet(UInt8[0xAA]; timestamp),
            packet(UInt8[0xBB]; timestamp, metadata = Dict{String, Any}()),
            packet(
                UInt8[0xCC];
                timestamp,
                metadata = Dict{String, Any}("mode" => "new"),
            ),
        ]
        cd(directory) do
            @test save_telemetry(packets, "roundtrip") === nothing
        end
        filename = joinpath(
            directory,
            "roundtrip_2024-02-03T04-05-06_2024-02-03T04-05-06.ser.gz",
        )
        @test isfile(filename)
        loaded = load_telemetry(filename)
        @test getproperty.(loaded, :timestamp) == getproperty.(packets, :timestamp)
        @test getproperty.(loaded, :data) == getproperty.(packets, :data)
        @test first(loaded).metadata === nothing
        @test isempty(loaded[2].metadata)
        @test last(loaded).metadata == Dict{String, Any}("mode" => "new")
        @test get_default_telemetry_packets() === loaded

        invalid = joinpath(directory, "invalid.ser.gz")
        stream = GzipCompressorStream(open(invalid, "w"))
        serialize(stream, "not telemetry packets")
        close(stream)
        @test_throws ArgumentError load_telemetry(invalid)
        @test get_default_telemetry_packets() === loaded

        malformed = joinpath(directory, "malformed.ser.gz")
        open(malformed, "w") do io
            write(io, "not gzip data")
        end
        @test_throws Exception load_telemetry(malformed)

        injected = joinpath(directory, "injected.ser.gz")
        stream = GzipCompressorStream(open(injected, "w"))
        serialize(stream, InjectedLoadFailure())
        close(stream)
        load_error = try
            load_telemetry(injected)
            nothing
        catch error
            error
        end

        @test load_error isa KeyError
        @test !isopen(INJECTED_LOAD_STREAM[])

        plain_key_injected = joinpath(directory, "plain-key-injected.ser.gz")
        stream = GzipCompressorStream(open(plain_key_injected, "w"))
        serialize(stream, InjectedPlainKeyLoadFailure())
        close(stream)
        plain_key_error = try
            load_telemetry(plain_key_injected)
            nothing
        catch error
            error
        end

        @test plain_key_error isa KeyError
        @test plain_key_error.key === :plain_key
        @test !isopen(INJECTED_PLAIN_KEY_LOAD_STREAM[])

        replacement_destination = joinpath(
            directory,
            "replace_2024-02-03T04-05-06_2024-02-03T04-05-06.ser.gz",
        )
        write(replacement_destination, "old destination")
        cd(directory) do
            @test save_telemetry(packets, "replace") === nothing
        end
        replacement = load_telemetry(replacement_destination)
        @test getproperty.(replacement, :timestamp) == getproperty.(packets, :timestamp)
        @test getproperty.(replacement, :data) == getproperty.(packets, :data)
        @test first(replacement).metadata === nothing
        @test isempty(replacement[2].metadata)
        @test last(replacement).metadata == Dict{String, Any}("mode" => "new")

        failed_packets = [TelemetryPacket{TestSource}(;
            timestamp = DateTime(2024, 2, 3, 4, 5, 6),
            data = UInt8[0xBB],
            metadata = Dict{String, Any}("failure" => InjectedSaveFailure()),
        )]
        destination = joinpath(
            directory,
            "atomic_2024-02-03T04-05-06_2024-02-03T04-05-06.ser.gz",
        )
        write(destination, "original destination")
        files_before_failure = readdir(directory)
        @test_throws ErrorException cd(directory) do
            save_telemetry(failed_packets, "atomic")
        end

        @test read(destination, String) == "original destination"

        @test !isopen(INJECTED_SAVE_STREAM[])
        @test readdir(directory) == files_before_failure
    end
end
