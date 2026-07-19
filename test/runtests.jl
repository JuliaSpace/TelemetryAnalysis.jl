## Description #############################################################################
#
# Loads and runs the TelemetryAnalysis test suites.
#
############################################################################################

using Test
using TelemetryAnalysis

include("helpers.jl")

@testset "TelemetryAnalysis" begin
    include("transfer_functions.jl")
    include("processing.jl")
    include("database.jl")
    include("misc.jl")
    include("sources.jl")
    include("persistence.jl")
    include("packets.jl")
end
