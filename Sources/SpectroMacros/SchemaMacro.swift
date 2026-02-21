import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct SchemaMacro {}

// MARK: - Property Analysis

private enum WrapperKind {
    case id, column, timestamp, foreignKey, hasMany, hasOne, belongsTo, manyToMany
}

private struct PropertyInfo {
    let name: String
    let typeName: String      // Base type (e.g. "String" even for String?)
    let fullType: String       // Full type as written (e.g. "String?")
    let isOptional: Bool
    let wrapper: WrapperKind
    let hasExplicitDefault: Bool
    let explicitDefault: String?
    let hasWrapperArguments: Bool  // Whether the @Wrapper has arguments, e.g. @ManyToMany(junctionTable: ...)
}

private let columnAttributeNames: Set<String> = ["ID", "Column", "Timestamp", "ForeignKey"]

private func classifyWrapper(_ attrNames: [String]) -> WrapperKind? {
    if attrNames.contains("ID") { return .id }
    if attrNames.contains("Column") { return .column }
    if attrNames.contains("Timestamp") { return .timestamp }
    if attrNames.contains("ForeignKey") { return .foreignKey }
    if attrNames.contains("HasMany") { return .hasMany }
    if attrNames.contains("HasOne") { return .hasOne }
    if attrNames.contains("BelongsTo") { return .belongsTo }
    if attrNames.contains("ManyToMany") { return .manyToMany }
    return nil
}

private func collectProperties(from structDecl: StructDeclSyntax) -> [PropertyInfo] {
    structDecl.memberBlock.members.compactMap { member in
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              varDecl.bindingSpecifier.text == "var",
              let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation?.type
        else { return nil }

        let attrs: [AttributeSyntax] = varDecl.attributes.compactMap {
            $0.as(AttributeSyntax.self)
        }
        let attrNames: [String] = attrs.compactMap {
            $0.attributeName.as(IdentifierTypeSyntax.self)?.name.text
        }

        guard let wrapper = classifyWrapper(attrNames) else { return nil }

        // Check if the wrapper attribute has explicit arguments (e.g. @ManyToMany(junctionTable: ...))
        let hasWrapperArgs = attrs.contains { attr in
            guard let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
                  classifyWrapper([name]) == wrapper else { return false }
            return attr.arguments != nil
        }

        let isOptional = typeAnnotation.is(OptionalTypeSyntax.self)
        let baseType: String
        if let opt = typeAnnotation.as(OptionalTypeSyntax.self) {
            baseType = opt.wrappedType.trimmedDescription
        } else {
            baseType = typeAnnotation.trimmedDescription
        }

        return PropertyInfo(
            name: pattern.identifier.text,
            typeName: baseType,
            fullType: typeAnnotation.trimmedDescription,
            isOptional: isOptional,
            wrapper: wrapper,
            hasExplicitDefault: binding.initializer != nil,
            explicitDefault: binding.initializer?.value.trimmedDescription,
            hasWrapperArguments: hasWrapperArgs
        )
    }
}

private func extractTableName(from node: AttributeSyntax) -> String? {
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
          let firstArg = arguments.first,
          let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
          let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self)
    else { return nil }
    return segment.content.text
}

private func defaultValueExpression(for prop: PropertyInfo) -> String {
    if prop.isOptional { return "nil" }
    switch prop.wrapper {
    case .id:                  return "UUID()"
    case .timestamp:           return "Date()"
    case .foreignKey:          return "UUID()"
    case .hasMany, .manyToMany: return "[]"
    case .hasOne, .belongsTo:   return "nil"
    case .column:
        switch prop.typeName {
        case "String": return "\"\""
        case "Int":    return "0"
        case "Bool":   return "false"
        case "Double": return "0.0"
        case "Float":  return "0.0"
        case "Date":   return "Date()"
        case "UUID":   return "UUID()"
        default:       return "\(prop.typeName)()"
        }
    }
}

// MARK: - Existing-member Detection

private struct ExistingMembers {
    var hasTableName = false
    var hasDefaultInit = false
}

private func detectExisting(in structDecl: StructDeclSyntax) -> ExistingMembers {
    var result = ExistingMembers()
    for member in structDecl.memberBlock.members {
        if let varDecl = member.decl.as(VariableDeclSyntax.self),
           let binding = varDecl.bindings.first,
           let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
           pattern.identifier.text == "tableName" {
            result.hasTableName = true
        }
        if let initDecl = member.decl.as(InitializerDeclSyntax.self),
           initDecl.signature.parameterClause.parameters.isEmpty {
            result.hasDefaultInit = true
        }
    }
    return result
}

// MARK: - MemberMacro

extension SchemaMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: SchemaDiagnostic.onlyStructs))
            return []
        }

        guard let tableName = extractTableName(from: node) else {
            context.diagnose(Diagnostic(node: node, message: SchemaDiagnostic.missingTableName))
            return []
        }

        let properties = collectProperties(from: structDecl)

        guard properties.contains(where: { $0.wrapper == .id }) else {
            context.diagnose(Diagnostic(node: node, message: SchemaDiagnostic.missingID))
            return []
        }

        let existing = detectExisting(in: structDecl)
        var decls: [DeclSyntax] = []

        // --- static let tableName ---
        if !existing.hasTableName {
            decls.append("static let tableName = \"\(raw: tableName)\"")
        }

        // --- init() ---
        if !existing.hasDefaultInit {
            // Skip @ManyToMany properties with wrapper arguments — they get their
            // default from the wrapper declaration (e.g. @ManyToMany(junctionTable: ...))
            // so we must not overwrite them with `self.tags = []`.
            let initProps = properties.filter {
                !($0.wrapper == .manyToMany && $0.hasWrapperArguments)
            }
            let assignments = initProps.map { prop in
                if let explicit = prop.explicitDefault, prop.hasExplicitDefault {
                    return "self.\(prop.name) = \(explicit)"
                }
                return "self.\(prop.name) = \(defaultValueExpression(for: prop))"
            }
            let body = assignments.joined(separator: "\n        ")
            let initDecl: DeclSyntax = """
            init() {
                    \(raw: body)
                }
            """
            decls.append(initDecl)
        }

        // --- convenience init(column params...) ---
        let columnProps = properties.filter { $0.wrapper == .column || $0.wrapper == .foreignKey }
        if !columnProps.isEmpty {
            var params: [String] = []
            for prop in columnProps {
                if prop.isOptional {
                    params.append("\(prop.name): \(prop.fullType) = nil")
                } else {
                    params.append("\(prop.name): \(prop.typeName)")
                }
            }

            // Skip @ManyToMany properties with wrapper arguments in convenience init too
            let convInitProps = properties.filter {
                !($0.wrapper == .manyToMany && $0.hasWrapperArguments)
            }
            let assignments = convInitProps.map { prop in
                switch prop.wrapper {
                case .id:                  return "self.\(prop.name) = UUID()"
                case .timestamp:           return "self.\(prop.name) = Date()"
                case .column, .foreignKey: return "self.\(prop.name) = \(prop.name)"
                case .hasMany, .manyToMany: return "self.\(prop.name) = []"
                case .hasOne, .belongsTo:   return "self.\(prop.name) = nil"
                }
            }

            let paramStr = params.joined(separator: ", ")
            let body = assignments.joined(separator: "\n        ")
            let convInit: DeclSyntax = """
            init(\(raw: paramStr)) {
                    \(raw: body)
                }
            """
            decls.append(convInit)
        }

        return decls
    }
}

// MARK: - ExtensionMacro

extension SchemaMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else { return [] }

        let typeName = structDecl.name.text
        var assignments: [String] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.text == "var"
            else { continue }

            let attrNames: [String] = varDecl.attributes.compactMap {
                $0.as(AttributeSyntax.self)?
                    .attributeName
                    .as(IdentifierTypeSyntax.self)?
                    .name.text
            }
            guard attrNames.contains(where: { columnAttributeNames.contains($0) }) else { continue }

            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeSyntax = binding.typeAnnotation?.type
            else { continue }

            let propName = pattern.identifier.text
            let isOptional = typeSyntax.is(OptionalTypeSyntax.self)
            let baseType: String
            if let optType = typeSyntax.as(OptionalTypeSyntax.self) {
                baseType = optType.wrappedType.trimmedDescription
            } else {
                baseType = typeSyntax.trimmedDescription
            }

            if isOptional {
                assignments.append(
                    "instance.\(propName) = values[\"\(propName)\"] as? \(baseType)"
                )
            } else {
                assignments.append(
                    "if let __v = values[\"\(propName)\"] as? \(baseType) { instance.\(propName) = __v }"
                )
            }
        }

        let body = assignments.joined(separator: "\n            ")

        let ext: DeclSyntax = """
        extension \(raw: typeName): Schema, SchemaBuilder {
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

    static let missingTableName = SchemaDiagnostic(
        message: "@Schema requires a table name argument, e.g. @Schema(\"users\")",
        diagnosticID: MessageID(domain: "SpectroMacros", id: "missingTableName"),
        severity: .error
    )

    static let missingID = SchemaDiagnostic(
        message: "@Schema requires at least one @ID property",
        diagnosticID: MessageID(domain: "SpectroMacros", id: "missingID"),
        severity: .error
    )
}
