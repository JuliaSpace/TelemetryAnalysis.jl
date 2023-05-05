module TelemetryAnalysis

import Base: @kwdef, print, show
import REPL

using CodecZlib
using DataFrames
using PrettyTables
using ProgressMeter
using REPL.TerminalMenus
using Reexport
using Serialization
using Unitful

const d = Unitful.d
const h = Unitful.hr
const m = Unitful.minute
const s = Unitful.s

export d, h, m, s

@reexport using Crayons
@reexport using Dates
@reexport using SIMD

############################################################################################
#                                          Types
############################################################################################

include("./types.jl")

############################################################################################
#                                        Constants
############################################################################################

const _DEFAULT_TELEMETRY_SOURCE = Ref{TelemetrySource}()
const _DEFAULT_TELEMETRY_PACKETS = Ref{Any}()
const _DEFAULT_TELEMETRY_DATABASE = Ref{TelemetryDatabase}()
const _INTERACTIVE_SOURCES = Vector{DataType}()

############################################################################################
#                                         Includes
############################################################################################

include("./io.jl")
include("./misc.jl")

include("./database/create.jl")
include("./database/dependencies.jl")
include("./database/get.jl")
include("./database/process.jl")
include("./database/search.jl")
include("./database/transfer_functions.jl")

include("./sources/api.jl")
include("./sources/get.jl")
include("./sources/init.jl")
include("./sources/save.jl")

end # module
