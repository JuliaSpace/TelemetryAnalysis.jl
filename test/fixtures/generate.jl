## Description #############################################################################
#
# Generates version-specific legacy telemetry serialization fixtures.
#
############################################################################################

using CodecZlib
using Dates
using Serialization
using TelemetryAnalysis

if !isdefined(TelemetryAnalysis, :LegacyFixtureSource)
    @eval TelemetryAnalysis begin
        """
            LegacyFixtureSource

        Telemetry source marker encoded in legacy serialization fixtures.

        # Fields

        This marker has no fields.
        """
        struct LegacyFixtureSource <: TelemetrySource end
    end
end

"""
    generate_fixture([root]) -> String

Generate a pre-P16 `TelemetryPacket` serialization fixture for the running Julia minor. This
function refuses to overwrite legacy fixtures when loaded with the post-P16 packet layout.
Julia Serialization is not a cross-version format, so output is stored in
`julia-MAJOR.MINOR` and tested only on that minor.
"""
# Generate deterministic legacy packets for only the running Julia minor.
function generate_fixture(root = @__DIR__)
    source = TelemetryAnalysis.LegacyFixtureSource
    metadata_type = fieldtype(TelemetryPacket{source}, :metadata)
    # Refuse to mislabel post-P16 packet layouts as legacy fixtures.
    metadata_type === Dict{String, Any} || error(
        "Refusing to generate a legacy fixture with the post-P16 packet layout.",
    )

    packets = [
        TelemetryPacket{source}(; timestamp = DateTime(2020), data = UInt8[0x01]),
        TelemetryPacket{source}(;
            timestamp = DateTime(2020, 1, 2),
            data = UInt8[0x02, 0x03],
            metadata = Dict{String, Any}("mode" => "legacy", "id" => 7),
        ),
    ]
    minor = "$(VERSION.major).$(VERSION.minor)"
    directory = joinpath(root, "julia-$minor")
    mkpath(directory)
    filename = joinpath(directory, "packets.ser.gz")
    stream = GzipCompressorStream(open(filename, "w"))
    try
        serialize(stream, packets)
    finally
        # Finalize and close the compressor even if serialization fails.
        close(stream)
    end
    return filename
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(generate_fixture())
end
