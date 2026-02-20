import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Generates `SchemaBuilder` conformance for a struct by inspecting its
/// property wrapper declarations at compile time.
///
/// For each `@ID`, `@Column`, `@Timestamp`, or `@ForeignKey` property
/// the macro emits an assignment in `build(from values: [String: Any]) -> Self`.
/// Relationship wrappers (`@HasMany`, `@HasOne`, `@BelongsTo`) are skipped
/// because they are not direct database columns.
public struct SchemaMacro: ExtensionMacro {

    // Attributes that map directly to database columns
    private static let columnAttributes = Set(["ID", "Column", "Timestamp", "ForeignKey"])

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            let diag = Diagnostic(
                node: node,
                message: SchemaDiagnostic.onlyStructs
            )
            context.diagnose(diag)
            return []
        }

        let typeName = structDecl.name.text
        var assignments: [String] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.text == "var"
            else { continue }

            // Collect attribute names on this property
            let attrNames: [String] = varDecl.attributes.compactMap { element in
                element.as(AttributeSyntax.self)?
                    .attributeName
                    .as(IdentifierTypeSyntax.self)?
                    .name.text
            }

            // Only include column-mapped properties
            guard attrNames.contains(where: { columnAttributes.contains($0) }) else { continue }

            // Extract binding: name and type annotation
            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeSyntax = binding.typeAnnotation?.type
            else { continue }

            let propName = pattern.identifier.text

            // Determine optionality and base type
            let isOptional = typeSyntax.is(OptionalTypeSyntax.self)
            let baseType: String
            if let optType = typeSyntax.as(OptionalTypeSyntax.self) {
                baseType = optType.wrappedType.trimmedDescription
            } else {
                baseType = typeSyntax.trimmedDescription
            }

            if isOptional {
                // Optional property: assign directly (nil if not in values)
                assignments.append(
                    "instance.\(propName) = values[\"\(propName)\"] as? \(baseType)"
                )
            } else {
                // Non-optional property: only assign if present
                assignments.append(
                    "if let __v = values[\"\(propName)\"] as? \(baseType) { instance.\(propName) = __v }"
                )
            }
        }

        let body = assignments.joined(separator: "\n            ")

        let ext: DeclSyntax = """
        extension \(raw: typeName): SchemaBuilder {
            public static func build(from values: [String: Any]) -> \(raw: typeName) {
                var instance = \(raw: typeName)()
                \(raw: body)
                return instance
            }
        }
        """

        guard let extDecl = ext.as(ExtensionDeclSyntax.self) else { return [] }
        return [extDecl]
    }
}

// MARK: - Diagnostics

private struct SchemaDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    static let onlyStructs = SchemaDiagnostic(
        message: "@Schema can only be applied to struct types",
        diagnosticID: MessageID(domain: "SpectroMacros", id: "onlyStructs"),
        severity: .error
    )
}
