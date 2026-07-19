## Description #############################################################################
#
# Defines test sources, packet constructors, database helpers, and shared test state.
#
############################################################################################

using CodecZlib
using Dates
using Serialization
using Unitful

"""
    TestSource

Telemetry source marker used by the test suite.

# Fields

This marker has no fields.
"""
struct TestSource <: TelemetrySource end

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

const LAST_SOURCE_RANGE = Ref{Tuple{DateTime, DateTime}}()

# Record ranged requests and return one deterministic packet.
function TelemetryAnalysis._api_get_telemetry(
    ::TestSource,
    start_time::DateTime,
    end_time::DateTime,
)
    LAST_SOURCE_RANGE[] = (start_time, end_time)
    return [TelemetryPacket{TestSource}(; timestamp = start_time, data = UInt8[1])]
end

# Return one deterministic packet for full-dump source tests.
function TelemetryAnalysis._api_get_telemetry(::TestSource)
    return [TelemetryPacket{TestSource}(; timestamp = DateTime(2024), data = UInt8[2])]
end

# Construct a test packet while allowing explicit data, timestamp, and metadata.
function packet(
    data = UInt8[1, 2, 3, 4];
    timestamp = DateTime(2024),
    metadata = nothing,
)
    return TelemetryPacket{TestSource}(; timestamp, data, metadata)
end

# Construct a test database whose default unpack callback returns packet data.
function test_database(; unpack = p -> p.data)
    return create_telemetry_database("test"; unpack_telemetry = unpack)
end

# Add a one-byte identity variable and return the database for test setup chaining.
function add_identity_variable!(database, label, position = 1; kwargs...)
    add_variable!(database, label, position, 1, identity; kwargs...)
    return database
end
