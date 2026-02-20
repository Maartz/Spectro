/// Automatically generates `SchemaBuilder` conformance for a schema struct.
///
/// Annotate your `Schema` struct with `@Schema` and you no longer need to
/// write `build(from values: [String: Any]) -> Self` by hand. The macro
/// inspects each `@ID`, `@Column`, `@Timestamp`, and `@ForeignKey` property
/// at compile time and generates the appropriate assignments.
///
/// ## Usage
///
/// ```swift
/// @Schema
/// struct User: Schema {
///     static let tableName = "users"
///     @ID    var id: UUID
///     @Column var name: String = ""
///     @Column var email: String = ""
///     @Timestamp var createdAt: Date = Date()
///     init() {}
/// }
/// ```
///
/// The macro expands to:
///
/// ```swift
/// extension User: SchemaBuilder {
///     public static func build(from values: [String: Any]) -> User {
///         var instance = User()
///         if let __v = values["id"]        as? UUID   { instance.id        = __v }
///         if let __v = values["name"]      as? String { instance.name      = __v }
///         if let __v = values["email"]     as? String { instance.email     = __v }
///         if let __v = values["createdAt"] as? Date   { instance.createdAt = __v }
///         return instance
///     }
/// }
/// ```
///
/// Relationship wrappers (`@HasMany`, `@HasOne`, `@BelongsTo`) are skipped
/// automatically — they are not direct database columns.
@attached(extension, conformances: SchemaBuilder, names: named(build))
public macro Schema() = #externalMacro(module: "SpectroMacros", type: "SchemaMacro")
