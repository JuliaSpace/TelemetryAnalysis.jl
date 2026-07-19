## Description #############################################################################
#
# Tests telemetry source defaults, full dumps, and time intervals.
#
############################################################################################

@testset "Source defaults and intervals" begin
    source = TestSource()
    start_time = DateTime(2024, 1, 1)
    packets = get_telemetry(source, start_time, start_time + Second(1))
    @test get_default_telemetry_packets() === packets

    full_dump = get_telemetry(source)

    @test get_default_telemetry_packets() === full_dump

    get_telemetry(source, start_time, 0s)
    @test LAST_SOURCE_RANGE[] == (start_time, start_time)

    @test try
        get_telemetry(source, start_time, 1Unitful.ms)
        LAST_SOURCE_RANGE[] == (start_time, start_time + Millisecond(1))
    catch
        false
    end

    @test try
        get_telemetry(source, start_time, 1.5s)
        LAST_SOURCE_RANGE[] == (start_time, start_time + Millisecond(1500))
    catch
        false
    end

    for interval in (
        -1Unitful.ms,
        1Unitful.μs,
        1.5Unitful.ms,
        NaN * s,
        Inf * s,
        (big(typemax(Int64)) + 1) * Unitful.ms,
    )
        @test_throws Exception get_telemetry(source, start_time, interval)
    end
    @test_throws Exception get_telemetry(source, start_time, 1Unitful.m)
end
