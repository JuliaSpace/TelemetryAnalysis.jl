## Description #############################################################################
#
# Tests telemetry database invariants, variable validation, aliases, and dependencies.
#
############################################################################################

@testset "Database invariants and aliases" begin
    database = test_database()
    add_identity_variable!(database, :temperature; alias = :temp)
    @test get_variable_description(:temperature, database) ===
        get_variable_description(:temp, database)
    @test_throws ArgumentError add_identity_variable!(database, :timestamp)
    @test_throws ArgumentError add_identity_variable!(database, :pressure;
        alias = :timestamp)
    @test_throws ArgumentError add_variable!(database, :derived, identity;
        dependencies = Symbol[])
    @test_throws KeyError get_variable_description(:missing, database)

    @test_throws ArgumentError add_identity_variable!(database, :pressure;
        alias = :temperature)
    @test_throws ArgumentError add_identity_variable!(database, :temp)
    @test_throws ArgumentError add_identity_variable!(database, :pressure; alias = :temp)

    @test_throws ArgumentError add_identity_variable!(database, :invalid;
        endianess = :middle)
    @test_throws ArgumentError add_identity_variable!(database, :invalid;
        default_view = :unknown)
    @test_throws ArgumentError add_variable!(database, :invalid, 0, 1, identity)
    @test_throws ArgumentError add_variable!(database, :invalid, 1, 0, identity)
    @test_throws ArgumentError add_variable!(database, :invalid, -1, 1, identity)
    @test_throws ArgumentError add_variable!(database, :invalid, 0, 0, identity)

    add_variable!(database, :frame_with_dependencies, 1, 1, identity;
        dependencies = [:temperature])
    add_variable!(database, :derived, identity; dependencies = [:temperature])
    @test database.variables[:derived].position == 0
    @test database.variables[:derived].size == 0

    dependencies = [:temperature]
    add_identity_variable!(database, :copied; dependencies)
    @test database.variables[:copied].dependencies !== dependencies
    push!(dependencies, :derived)
    @test database.variables[:copied].dependencies == [:temperature]

    replacement = test_database()
    add_identity_variable!(replacement, :value; alias = :old)
    add_identity_variable!(replacement, :value; alias = :new)
    add_identity_variable!(replacement, :old)
    @test get_variable_description(:new, replacement).label == :value
    @test get_variable_description(:old, replacement).label == :old

    mutated = test_database()
    add_identity_variable!(mutated, :value)
    descriptor = mutated.variables[:value]
    mutated.variables[:value] = TelemetryVariableDescription(
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
    @test_throws ArgumentError get_variable_description(:value, mutated)

    ambiguous = test_database()
    add_identity_variable!(ambiguous, :first; alias = :shared)
    second = ambiguous.variables[:first]
    ambiguous.variables[:second] = TelemetryVariableDescription(
        :shared,
        second.default_view,
        second.dependencies,
        second.description,
        second.endianess,
        :second,
        second.position,
        second.size,
        second.tf,
        second.btf,
        second.rtf
    )
    @test_throws ArgumentError get_variable_description(:shared, ambiguous)

    mismatched = test_database()
    mismatched.variables[:wrong] = descriptor
    @test_throws ArgumentError get_variable_description(:wrong, mismatched)
end
