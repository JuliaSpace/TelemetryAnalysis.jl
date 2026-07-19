## Description #############################################################################
#
# Tests threaded telemetry processing, dependencies, output views, validation, and ordering.
#
############################################################################################

"""
    OffsetByteVector(data, first_index)

Minimal offset-indexed byte vector used to verify logical frame positions.

# Fields

- `data::Vector{UInt8}`: Parent byte storage.
- `first_index::Int`: First logical index exposed by the vector.
"""
struct OffsetByteVector <: AbstractVector{UInt8}
    data::Vector{UInt8}
    first_index::Int
end

# Report the parent storage length as the vector's one-dimensional size.
Base.size(vector::OffsetByteVector) = (length(vector.data),)

# Shift the vector axis to begin at its configured logical index.
Base.axes(vector::OffsetByteVector) =
    (vector.first_index:(vector.first_index + length(vector.data) - 1),)

# Use Cartesian indexing so bounds respect the custom axis.
Base.IndexStyle(::Type{OffsetByteVector}) = IndexCartesian()

# Translate a checked logical index into the parent storage index.
function Base.getindex(vector::OffsetByteVector, index::Int)
    checkbounds(vector, index)
    return vector.data[index - vector.first_index + 1]
end

@testset "Default and empty processing" begin
    database = create_telemetry_database("default unpack")
    add_identity_variable!(database, :value)

    output = process_telemetry_packets([packet()], [:value]; database,
        show_progress = false)
    @test output.value == [UInt8[1]]

    empty_packets = TelemetryPacket{TestSource}[]
    selected = process_telemetry_packets(empty_packets, [:value]; database,
        show_progress = false)
    @test isempty(selected)
    @test propertynames(selected) == [:timestamp, :value]
    @test eltype(selected.timestamp) === DateTime
    @test eltype(selected.value) === Any

    add_identity_variable!(database, :raw_value; default_view = :raw)
    default_output = process_telemetry_packets(empty_packets; database,
        show_progress = false)
    @test isempty(default_output)
    @test propertynames(default_output) == [:timestamp, :raw_value_raw, :value]
    @test eltype.(eachcol(default_output)) == [DateTime, Any, Any]
end

@testset "Multi-packet threaded processing" begin
    database = test_database()
    btf_count = Threads.Atomic{Int}(0)
    rtf_count = Threads.Atomic{Int}(0)
    tf_count = Threads.Atomic{Int}(0)
    # Count byte-stage execution across packets without introducing a data race.
    btf = bytes -> begin
        Threads.atomic_add!(btf_count, 1)
        bytes
    end
    # Count raw-stage execution and reduce each byte view to one value.
    rtf = bytes -> begin
        Threads.atomic_add!(rtf_count, 1)
        first(bytes)
    end
    # Count processed-stage execution while preserving the raw value.
    tf = raw -> begin
        Threads.atomic_add!(tf_count, 1)
        raw
    end
    add_variable!(database, :value, 1, 1, tf, btf, rtf)
    packets = [
        packet(UInt8[mod1(index, 251)]; timestamp = DateTime(2024) + Millisecond(index))
        for index in 1:64
    ]
    output = process_telemetry_packets(packets, [:value]; database,
        show_progress = false)
    @test output.value == UInt8[mod1(index, 251) for index in 1:64]
    @test (btf_count[], rtf_count[], tf_count[]) == (64, 64, 64)
end

@testset "Dependency graphs" begin
    counts = Dict(stage => Dict{Symbol, Int}() for stage in (:btf, :rtf, :tf))
    database = test_database()

    for index in 1:6
        label = Symbol(:v, index)
        dependencies = index == 1 ? nothing : [Symbol(:v, index - 1)]
        # Count byte-stage execution independently for every chain node.
        btf = bytes -> begin
            counts[:btf][label] = get(counts[:btf], label, 0) + 1
            bytes
        end
        # Count raw-stage execution and materialize the node's byte value.
        rtf = bytes -> begin
            counts[:rtf][label] = get(counts[:rtf], label, 0) + 1
            Int(first(bytes))
        end
        # Count processed-stage execution and accumulate the preceding chain result.
        tf = (raw, context) -> begin
            counts[:tf][label] = get(counts[:tf], label, 0) + 1
            isnothing(dependencies) ? raw : raw + context[first(dependencies)].processed
        end
        add_variable!(database, label, index, 1, tf, btf, rtf; dependencies)
    end

    labels = [Symbol(:v, index) for index in 1:6]
    frame = UInt8[1, 2, 3, 4, 5, 6]
    forward = process_telemetry_packets([packet(frame)], labels; database,
        show_progress = false)
    @test forward.v6 == [21]
    @test all(
        counts[stage] == Dict(label => 1 for label in labels)
        for stage in keys(counts)
    )

    foreach(empty!, values(counts))
    reverse_output = process_telemetry_packets([packet(frame)], reverse(labels); database,
        show_progress = false)
    @test reverse_output.v6 == [21]
    @test all(
        counts[stage] == Dict(label => 1 for label in labels)
        for stage in keys(counts)
    )

    callback_count = Ref(0)
    cyclic = test_database()
    # Prove graph validation occurs before callback execution.
    cyclic_btf = bytes -> begin
        callback_count[] += 1
        bytes
    end
    add_variable!(cyclic, :a, 1, 1, identity, cyclic_btf;
        dependencies = [:b])
    add_variable!(cyclic, :b, 1, 1, identity, cyclic_btf;
        dependencies = [:a])
    cycle_error = try
        process_telemetry_packets([packet()], [:a]; database = cyclic,
            show_progress = false)
        nothing
    catch error
        error
    end
    @test cycle_error isa ErrorException
    @test occursin("Cyclic dependency", sprint(showerror, cycle_error))
    @test callback_count[] == 0

    missing = test_database()
    add_variable!(missing, :a, 1, 1, identity, cyclic_btf;
        dependencies = [:absent])
    missing_error = try
        process_telemetry_packets([packet()], [:a]; database = missing,
            show_progress = false)
        nothing
    catch error
        error
    end
    @test missing_error isa KeyError
    @test occursin(":absent", sprint(showerror, missing_error))
    @test callback_count[] == 0

    cached = test_database()
    add_identity_variable!(cached, :base, 1)
    add_identity_variable!(cached, :replacement, 2)
    # Read the initially declared dependency from the canonical callback context.
    initial_tf = (raw, context) -> context[:base].processed
    add_variable!(cached, :derived, 3, 1, initial_tf; dependencies = [:base])
    initial = process_telemetry_packets([packet()], [:derived]; database = cached,
        show_progress = false)
    @test initial.derived == [UInt8[1]]
    # Read the replacement dependency after redefining the derived variable.
    replacement_tf = (raw, context) -> context[:replacement].processed
    add_variable!(cached, :derived, 3, 1, replacement_tf;
        dependencies = [:replacement])

    replaced = process_telemetry_packets([packet()], [:derived]; database = cached,
        show_progress = false)
    @test replaced.derived == [UInt8[2]]

    descriptor = cached.variables[:derived]
    cached.variables[:derived] = TelemetryVariableDescription(
        descriptor.alias,
        descriptor.default_view,
        [:base],
        descriptor.description,
        descriptor.endianess,
        descriptor.label,
        descriptor.position,
        descriptor.size,
        initial_tf,
        descriptor.btf,
        descriptor.rtf
    )
    cached._variable_dependencies[:derived] = [:replacement]
    mutated = process_telemetry_packets([packet()], [:derived]; database = cached,
        show_progress = false)
    @test mutated.derived == [UInt8[1]]
end

@testset "Stage masks and duplicate views" begin
    counts = Dict(:btf => 0, :rtf => 0, :tf => 0)
    database = test_database()
    # Count byte-stage execution for each requested view combination.
    btf = bytes -> begin
        counts[:btf] += 1
        bytes
    end
    # Count raw-stage execution for stage-mask assertions.
    rtf = bytes -> begin
        counts[:rtf] += 1
        first(bytes)
    end
    # Count processed-stage execution for stage-mask assertions.
    tf = raw -> begin
        counts[:tf] += 1
        raw + 1
    end
    add_variable!(database, :value, 1, 1, tf, btf, rtf; alias = :alias)
    # Reset all stage counters between independent view-mask requests.
    reset_counts! = () -> foreach(stage -> counts[stage] = 0, keys(counts))

    process_telemetry_packets([packet()], [:value => :byte_array]; database,
        show_progress = false)
    @test counts == Dict(:btf => 1, :rtf => 0, :tf => 0)

    reset_counts!()
    process_telemetry_packets([packet()], [:value => :raw]; database,
        show_progress = false)
    @test counts == Dict(:btf => 1, :rtf => 1, :tf => 0)

    reset_counts!()
    process_telemetry_packets([packet()], [:value => :processed]; database,
        show_progress = false)
    @test counts == Dict(:btf => 1, :rtf => 1, :tf => 1)

    reset_counts!()
    output = process_telemetry_packets(
        [packet()],
        [:value => :byte_array, :alias => :raw, :value => :processed];
        database,
        show_progress = false
    )
    @test counts == Dict(:btf => 1, :rtf => 1, :tf => 1)
    @test propertynames(output) == [:timestamp, :value_byte_array, :alias_raw, :value]
end

@testset "Shared dependencies and callback contexts" begin
    counts = Dict(stage => Dict{Symbol, Int}() for stage in (:btf, :rtf, :tf))
    database = test_database()
    graph = Dict(
        :a => nothing,
        :b => [:a],
        :c => [:a],
        :d => [:b, :c],
    )

    for (index, label) in enumerate((:a, :b, :c, :d))
        dependencies = graph[label]
        # Count byte-stage execution once for every node in the diamond graph.
        btf = bytes -> begin
            counts[:btf][label] = get(counts[:btf], label, 0) + 1
            bytes
        end
        # Count raw-stage execution and expose a scalar node value.
        rtf = bytes -> begin
            counts[:rtf][label] = get(counts[:rtf], label, 0) + 1
            Int(first(bytes))
        end
        # Count processed-stage execution and combine all declared dependencies.
        tf = (raw, context) -> begin
            counts[:tf][label] = get(counts[:tf], label, 0) + 1
            if isnothing(dependencies)
                raw
            else
                raw + sum(context[dependency].processed for dependency in dependencies)
            end
        end
        add_variable!(database, label, index, 1, tf, btf, rtf; dependencies)
    end

    output = process_telemetry_packets([packet(UInt8[1, 2, 3, 4])], [:d];
        database, show_progress = false)
    @test output.d == [11]
    @test all(
        counts[stage] == Dict(label => 1 for label in (:a, :b, :c, :d))
        for stage in keys(counts)
    )

    contexts = Any[]
    context_keys = Set{Symbol}[]
    context_lock = ReentrantLock()
    alias_database = test_database()
    add_variable!(alias_database, :base, 1, 1, identity,
        default_bit_transfer_function, first; alias = :source)
    # Record canonical dependency keys observed by raw callbacks.
    context_rtf = (bytes, context) -> begin
        lock(context_lock) do
            push!(context_keys, Set(keys(context)))
        end
        first(bytes) + context[:base].processed
    end
    # Record fresh per-packet contexts and their canonical keys.
    context_tf = (raw, context) -> begin
        lock(context_lock) do
            push!(contexts, context)
            push!(context_keys, Set(keys(context)))
        end
        raw
    end
    add_variable!(alias_database, :derived, 2, 1, context_tf,
        default_bit_transfer_function, context_rtf; alias = :result,
        dependencies = [:source])
    packets = [
        packet(UInt8[1, 2]; timestamp = DateTime(2024)),
        packet(UInt8[3, 4]; timestamp = DateTime(2024) + Second(1)),
    ]
    alias_output = process_telemetry_packets(packets, [:result];
        database = alias_database, show_progress = false)
    @test alias_output.result == [3, 7]
    @test length(contexts) == 2
    @test contexts[1] !== contexts[2]
    @test all(keys == Set([:base]) for keys in context_keys)
end

@testset "Concrete execution nodes" begin
    database = test_database()
    add_variable!(database, :value, 1, 1, identity,
        default_bit_transfer_function, first)
    descriptor = database.variables[:value]
    node = TelemetryAnalysis._execution_node(descriptor)

    @test fieldtype(typeof(node), :btf) === typeof(descriptor.btf)
    @test fieldtype(typeof(node), :rtf) === typeof(descriptor.rtf)
    @test fieldtype(typeof(node), :tf) === typeof(descriptor.tf)

    frame = @view UInt8[1][1:1]
    @test (@inferred TelemetryAnalysis._execute_btf(node, frame)) === frame
    state = TelemetryAnalysis.PacketExecutionState(1)
    @test (@inferred TelemetryAnalysis._execute_node!(
        state,
        node,
        UInt8[1],
        1,
        TelemetryAnalysis._STAGES_THROUGH_PROCESSED
    )) === nothing
    @test state.context[:value] == (; raw = 0x01, processed = 0x01)
end

@testset "Bit transfer result contract" begin
    invalid_database = test_database()
    # Return a non-byte result to verify the bit-transfer result contract.
    add_variable!(invalid_database, :invalid, 1, 1, identity, _ -> true)

    for view in (:byte_array, :raw, :processed)
        error = try
            process_telemetry_packets([packet()], [:invalid => view];
                database = invalid_database, show_progress = false)
            nothing
        catch exception
            exception
        end
        @test error isa CompositeException
        message = sprint(showerror, error)
        @test occursin("variable :invalid", message)
        @test occursin("AbstractVector{UInt8}", message)
        @test occursin("Bool", message)
    end

    valid_database = test_database()
    # Return a non-Vector byte view to verify valid AbstractVector support.
    view_btf = frame -> @view frame[:]
    add_variable!(valid_database, :value, 1, 2, identity, view_btf, first)
    output = process_telemetry_packets(
        [packet(UInt8[2, 3])],
        [:value => :byte_array, :value => :processed];
        database = valid_database,
        show_progress = false
    )
    @test only(output.value_byte_array) isa Vector{UInt8}
    @test output.value == UInt8[2]
end

@testset "Views and frame ownership" begin
    database = test_database()
    add_identity_variable!(database, :value)

    @test_throws ArgumentError process_telemetry_packets(
        [packet()], [:value => :unknown]; database, show_progress = false)
    @test_throws ArgumentError process_telemetry_packets(
        TelemetryPacket{TestSource}[], [:value => :unknown]; database,
        show_progress = false)

    invalid_default = test_database()
    add_identity_variable!(invalid_default, :value)
    descriptor = invalid_default.variables[:value]
    invalid_default.variables[:value] = TelemetryVariableDescription(
        descriptor.alias,
        :unknown,
        descriptor.dependencies,
        descriptor.description,
        descriptor.endianess,
        descriptor.label,
        descriptor.position,
        descriptor.size,
        descriptor.tf,
        descriptor.btf,
        descriptor.rtf
    )
    @test_throws ArgumentError process_telemetry_packets(
        [packet()], [:value]; database = invalid_default, show_progress = false)
    @test_throws ArgumentError process_telemetry_packets(
        TelemetryPacket{TestSource}[], [:value]; database = invalid_default,
        show_progress = false)

    invalid_endianess = test_database()
    add_identity_variable!(invalid_endianess, :value)
    descriptor = invalid_endianess.variables[:value]
    invalid_endianess.variables[:value] = TelemetryVariableDescription(
        descriptor.alias,
        descriptor.default_view,
        descriptor.dependencies,
        descriptor.description,
        :middle,
        descriptor.label,
        descriptor.position,
        descriptor.size,
        descriptor.tf,
        descriptor.btf,
        descriptor.rtf
    )
    @test_throws ArgumentError process_telemetry_packets(
        [packet()], [:value]; database = invalid_endianess, show_progress = false)

    add_identity_variable!(database, :value_raw)
    @test_throws ArgumentError process_telemetry_packets(
        [packet()], [:value => :raw, :value_raw => :processed]; database,
        show_progress = false)

    little = database.variables[:value]
    big_database = test_database()
    add_variable!(big_database, :value, 1, 3, identity; endianess = :bigendian)
    bytes = UInt8[1, 2, 3]
    little_frame = TelemetryAnalysis._get_variable_telemetry_frame(bytes, little)
    big_frame = TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, big_database.variables[:value])
    @test little_frame isa SubArray
    @test parent(little_frame) === bytes
    @test little_frame == UInt8[1]
    @test stride(little_frame, 1) == 1
    @test big_frame == UInt8[3, 2, 1]
    @test big_frame isa SubArray
    @test parent(big_frame) === bytes
    @test stride(big_frame, 1) == -1

    add_variable!(database, :derived, identity; dependencies = [:value])
    empty_frame = TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, database.variables[:derived])
    @test empty_frame isa SubArray
    @test isempty(empty_frame)
    @test parent(empty_frame) === bytes

    btf_read = Ref{Any}()
    rtf_read = Ref{Any}()
    callback_database = test_database()
    # Capture the ephemeral bit-transfer view and its parent storage.
    btf = frame -> begin
        btf_read[] = (collect(frame), frame isa SubArray, parent(frame))
        frame
    end
    # Capture the raw callback view before materializing its value.
    rtf = byte_array -> begin
        rtf_read[] = (collect(byte_array), byte_array isa SubArray, parent(byte_array))
        collect(byte_array)
    end
    add_variable!(callback_database, :value, 1, 3, identity, btf, rtf;
        endianess = :bigendian)
    callback_output = process_telemetry_packets([packet(bytes)], [:value];
        database = callback_database, show_progress = false)
    @test callback_output.value == [UInt8[3, 2, 1]]
    @test btf_read[][1:2] == (UInt8[3, 2, 1], true)
    @test rtf_read[][1:2] == (UInt8[3, 2, 1], true)
    @test btf_read[][3] === bytes
    @test rtf_read[][3] === bytes
end

@testset "Offset-indexed frame views" begin
    bytes = OffsetByteVector(UInt8[10, 20, 30, 40], 5)

    little_database = test_database()
    add_variable!(little_database, :value, 2, 2, identity)
    little_frame = TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, little_database.variables[:value])
    @test collect(little_frame) == UInt8[20, 30]
    @test parent(little_frame) === bytes

    big_database = test_database()
    add_variable!(big_database, :value, 2, 2, identity; endianess = :bigendian)
    big_frame = TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, big_database.variables[:value])
    @test collect(big_frame) == UInt8[30, 20]
    @test parent(big_frame) === bytes

    add_variable!(little_database, :derived, identity; dependencies = [:value])
    empty_frame = TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, little_database.variables[:derived])
    @test isempty(empty_frame)
    @test parent(empty_frame) === bytes
    @test parentindices(empty_frame) == (5:4,)

    add_variable!(little_database, :late, 5, 1, identity)
    @test_throws ArgumentError TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, little_database.variables[:late])

    add_variable!(little_database, :wide, 4, 2, identity)
    @test_throws ArgumentError TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, little_database.variables[:wide])

    add_variable!(little_database, :overflow_position, typemax(Int), 1, identity)
    @test_throws ArgumentError TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, little_database.variables[:overflow_position])

    add_variable!(little_database, :overflow_size, 1, typemax(Int), identity)
    @test_throws ArgumentError TelemetryAnalysis._get_variable_telemetry_frame(
        bytes, little_database.variables[:overflow_size])
end

@testset "Processing selection order" begin
    database = test_database()
    add_identity_variable!(database, :zeta)
    add_identity_variable!(database, :alpha)
    add_identity_variable!(database, :middle)

    all_output = process_telemetry_packets([packet()]; database, show_progress = false)
    @test propertynames(all_output) == [:timestamp, :alpha, :middle, :zeta]

    explicit_output = process_telemetry_packets(
        [packet()],
        [:zeta, :alpha, :middle];
        database,
        show_progress = false
    )
    @test propertynames(explicit_output) == [:timestamp, :zeta, :alpha, :middle]
end

@testset "Columnar filtering and ordering" begin
    # Reject every packet to verify the empty filtered schema.
    all_invalid_database = test_database(; unpack = _ -> nothing)
    add_identity_variable!(all_invalid_database, :value)
    all_invalid = process_telemetry_packets(
        [packet(), packet()],
        [:value];
        database = all_invalid_database,
        show_progress = false
    )
    @test isempty(all_invalid)
    @test propertynames(all_invalid) == [:timestamp, :value]
    @test eltype(all_invalid.timestamp) === DateTime
    @test eltype(all_invalid.value) === Any

    database = test_database()
    add_variable!(database, :value, 1, 1, identity,
        default_bit_transfer_function, first)
    epoch = DateTime(2024)
    unsorted_packets = [
        packet(UInt8[1]; timestamp = epoch + Second(1)),
        packet(UInt8[2]; timestamp = epoch),
        packet(UInt8[3]; timestamp = epoch + Second(1)),
        packet(UInt8[4]; timestamp = epoch),
    ]
    unsorted = process_telemetry_packets(unsorted_packets, [:value]; database,
        show_progress = false)
    @test unsorted.value == UInt8[2, 4, 1, 3]
    @test unsorted.timestamp == [epoch, epoch, epoch + Second(1), epoch + Second(1)]
    @test eltype(unsorted.value) === UInt8

    sorted_packets = [
        packet(UInt8[5]; timestamp = epoch),
        packet(UInt8[6]; timestamp = epoch),
        packet(UInt8[7]; timestamp = epoch + Second(1)),
    ]
    sorted = process_telemetry_packets(sorted_packets, [:value]; database,
        show_progress = false)
    @test sorted.value == UInt8[5, 6, 7]
    @test TelemetryAnalysis._stable_valid_indices(
        Bool[true, true, true],
        [packet.timestamp for packet in sorted_packets]
    ) == [1, 2, 3]

    # Omit packets beginning with zero while preserving accepted packet values.
    filtering_database = test_database(
        unpack = packet -> iszero(first(packet.data)) ? nothing : packet.data
    )
    # Transform accepted values to distinguish raw and processed output columns.
    add_variable!(filtering_database, :value, 1, 1, value -> value + 1,
        default_bit_transfer_function, first)
    filtered = process_telemetry_packets(
        [packet(UInt8[1]), packet(UInt8[0]), packet(UInt8[3])],
        [:value => :raw, :value => :processed];
        database = filtering_database,
        show_progress = false
    )
    @test filtered.value_raw == UInt8[1, 3]
    @test filtered.value == UInt8[2, 4]

    heterogeneous_database = test_database()
    # Alternate result types to verify non-converting heterogeneous narrowing.
    heterogeneous_tf = raw -> isodd(first(raw)) ? Int(first(raw)) : string(first(raw))
    add_variable!(heterogeneous_database, :value, 1, 1, heterogeneous_tf)
    heterogeneous = process_telemetry_packets(
        [packet(UInt8[1]), packet(UInt8[2])],
        [:value];
        database = heterogeneous_database,
        show_progress = false
    )
    @test heterogeneous.value == Any[1, "2"]
    @test eltype(heterogeneous.value) === Any

    integer_values = Any[UInt64(typemax(UInt64)), Int64(-1)]
    joined_integers = TelemetryAnalysis._narrow_output_column(integer_values)
    @test eltype(joined_integers) === Integer
    @test joined_integers == integer_values
    @test typeof(joined_integers[1]) === UInt64
    @test typeof(joined_integers[2]) === Int64

    exact_rational = 1 // 3
    real_values = Any[exact_rational, 0.5]
    joined_reals = TelemetryAnalysis._narrow_output_column(real_values)
    @test eltype(joined_reals) === Real
    @test joined_reals[1] === exact_rational
    @test typeof(joined_reals[1]) === Rational{Int}
    @test joined_reals[2] === 0.5

    mixed_values = Any[1, "2"]
    @test TelemetryAnalysis._narrow_output_column(mixed_values) === mixed_values
    homogeneous_values = Any[UInt8(1), UInt8(2)]
    joined_homogeneous = TelemetryAnalysis._narrow_output_column(homogeneous_values)
    @test joined_homogeneous == UInt8[1, 2]
    @test eltype(joined_homogeneous) === UInt8
end

@testset "Output collision validation" begin
    callback_count = Ref(0)
    database = test_database()
    # Count callbacks to prove collision validation precedes packet execution.
    btf = bytes -> begin
        callback_count[] += 1
        bytes
    end
    add_variable!(database, :value, 1, 1, identity, btf; alias = :alias)
    add_identity_variable!(database, :value_raw)

    collisions = [
        [:value => :processed, :value => :processed],
        [:value => :byte_array, :value => :byte_array_bin],
        [:value => :byte_array_hex, :value => :byte_array],
        [:value => :raw, :value_raw => :processed],
    ]
    for selections in collisions
        error = try
            process_telemetry_packets([packet()], selections; database,
                show_progress = false)
            nothing
        catch exception
            exception
        end
        @test error isa ArgumentError
        @test occursin("collides", sprint(showerror, error))
    end
    @test callback_count[] == 0

    timestamp_output = TelemetryAnalysis.OutputSpec(:value, 1, :processed, :timestamp)
    @test_throws ArgumentError TelemetryAnalysis._validate_output_names([timestamp_output])
end

@testset "Owned byte-array outputs" begin
    shared_buffer = UInt8[8, 9]
    database = test_database()
    # Return one shared buffer to verify every public byte-array output is copied.
    add_variable!(database, :value, 1, 2, identity, _ -> shared_buffer)
    first_packet = packet(UInt8[1, 2])
    second_packet = packet(UInt8[3, 4])
    output = process_telemetry_packets(
        [first_packet, second_packet],
        [:value => :byte_array];
        database,
        show_progress = false
    )
    @test eltype(output.value_byte_array) === Vector{UInt8}
    @test output.value_byte_array == [UInt8[8, 9], UInt8[8, 9]]
    @test output.value_byte_array[1] !== output.value_byte_array[2]
    @test all(value !== shared_buffer for value in output.value_byte_array)
    @test all(value !== first_packet.data for value in output.value_byte_array)
    shared_buffer[1] = 0xff
    first_packet.data[1] = 0xff
    @test output.value_byte_array == [UInt8[8, 9], UInt8[8, 9]]

    formatting_database = test_database()
    add_variable!(formatting_database, :value, 1, 2, identity)
    binary = process_telemetry_packets(
        [packet(UInt8[0x0f, 0xa0])],
        [:value => :byte_array_bin];
        database = formatting_database,
        show_progress = false
    )
    hexadecimal = process_telemetry_packets(
        [packet(UInt8[0x0f, 0xa0])],
        [:value => :byte_array_hex];
        database = formatting_database,
        show_progress = false
    )
    @test only(binary.value_byte_array) == "0b1010000000001111"
    @test only(hexadecimal.value_byte_array) == "0xA00F"
end

@testset "Threaded exception termination" begin
    project_directory = dirname(@__DIR__)
    # Run callback and timestamp failures under four threads to detect hangs or lost errors.
    script = """
        using TelemetryAnalysis, Dates
        \"\"\"
            FailureSource

        Telemetry source marker used by the threaded failure subprocess.

        # Fields

        This marker has no fields.
        \"\"\"
        struct FailureSource <: TelemetrySource end
        packets = [TelemetryPacket{FailureSource}(;
            timestamp = DateTime(2024), data = UInt8[1]) for _ in 1:64]
        # Expose packet bytes before injecting a processed callback failure.
        callback_database = create_telemetry_database(
            \"callback\"; unpack_telemetry = packet -> packet.data)
        # Throw from worker callbacks to verify propagation without deadlock.
        add_variable!(callback_database, :value, 1, 1, identity,
            _ -> error(\"callback failure\"))
        try
            process_telemetry_packets(packets, [:value];
                database = callback_database, show_progress = false)
            error(\"callback exception was not propagated\")
        catch error
            occursin(\"callback failure\", sprint(showerror, error)) || rethrow()
        end
        # Throw while obtaining timestamps to verify the second worker failure path.
        timestamp_database = create_telemetry_database(
            \"timestamp\";
            unpack_telemetry = packet -> packet.data,
            get_telemetry_timestamp = _ -> error(\"timestamp failure\"))
        add_variable!(timestamp_database, :value, 1, 1, identity)
        try
            process_telemetry_packets(packets, [:value];
                database = timestamp_database, show_progress = false)
            error(\"timestamp exception was not propagated\")
        catch error
            occursin(\"timestamp failure\", sprint(showerror, error)) || rethrow()
        end
    """
    command = `$(Base.julia_cmd()) --project=$project_directory --threads=4 -e $script`
    process = run(pipeline(command; stdout = devnull, stderr = devnull); wait = false)
    # Poll with a fixed timeout so a threaded deadlock fails deterministically.
    completion = timedwait(() -> process_exited(process), 20)
    if completion === :timed_out
        kill(process)
        wait(process)
    end
    @test completion === :ok
    @test completion === :ok && success(process)
end
