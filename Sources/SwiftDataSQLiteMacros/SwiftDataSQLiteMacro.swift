import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct SQLiteTableMacro: ExtensionMacro {
    
    private struct ForeignKeyInfo {
        let columnName: String
        let recordPropertyName: String
        let typeName: String
        let propertyName: String
        let keyPath: String
    }

    private struct PropertyInfo {
        let name: String
        let typeName: String
        let isArray: Bool
        let hasRelationshipAttribute: Bool
        let foreignKey: ForeignKeyInfo?
        let customColumnName: String?
    }

    private struct InitializerParameterInfo {
        let argumentLabel: String?
        let localName: String
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let typeName = type.trimmedDescription
        let tableName = parseTableName(from: node) ?? "\(typeName.lowercased())s"
        let properties = collectProperties(from: declaration)
        let firstInitializerParameters = parseFirstInitializerParameters(from: declaration)

        let initProperties = properties.filter { !($0.isArray && $0.hasRelationshipAttribute) }
        let updatableProperties = initProperties.filter { $0.name != "id" }

        let recordFieldLines = buildRecordFieldLines(from: initProperties)
        let recordFieldsBlock = recordFieldLines.joined(separator: "\n")

        let codingKeysBlock = buildCodingKeysEnum(from: initProperties)
        let decodingSection: String
        if let codingKeys = codingKeysBlock {
            decodingSection = "\n\(codingKeys)"
        } else {
            decodingSection = "\nnonisolated(unsafe)static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase"
        }

        var fkSetupLines: [String] = []
        var initArgumentLines: [String] = []
        var seenForeignKeyProperties: Set<String> = []

        let propertiesByName = Dictionary(uniqueKeysWithValues: initProperties.map { ($0.name, $0) })

        let initializerParameters = firstInitializerParameters.isEmpty
            ? initProperties.map { InitializerParameterInfo(argumentLabel: $0.name, localName: $0.name) }
            : firstInitializerParameters

        for parameter in initializerParameters {
            if
                let property = propertiesByName[parameter.localName],
                let foreignKey = property.foreignKey
            {
                if !seenForeignKeyProperties.contains(property.name) {
                    let fkVarName = "\(property.name)ForeignKeyValue"
                    let descriptorVarName = "\(property.name)FetchDescriptor"
                    let relatedVarName = "\(property.name)"
                    fkSetupLines.append("""
                    let \(fkVarName) = record.\(foreignKey.recordPropertyName)
                    var \(descriptorVarName) = FetchDescriptor<\(foreignKey.typeName)>(predicate: #Predicate { $0.\(foreignKey.propertyName) == \(fkVarName) })
                    \(descriptorVarName).fetchLimit = 1
                    let \(relatedVarName) = try modelContext.fetch(\(descriptorVarName))[0]
                    """)
                    seenForeignKeyProperties.insert(property.name)
                }
                let valueExpression = property.name
                initArgumentLines.append(buildInitializerArgument(label: parameter.argumentLabel, valueExpression: valueExpression))
            } else {
                let valueExpression = "record.\(parameter.localName)"
                initArgumentLines.append(buildInitializerArgument(label: parameter.argumentLabel, valueExpression: valueExpression))
            }
        }

        let initArgsBlock = initArgumentLines.joined(separator: ",\n")
        let updateAssignmentLines = updatableProperties.map { "existingModel.\($0.name) = model.\($0.name)" }
        let updateAssignmentsBlock = updateAssignmentLines.joined(separator: "\n")
        let fkSetupBlock = fkSetupLines.joined(separator: "\n")
        let maybeFkBlock = fkSetupBlock.isEmpty ? "" : "\n\(fkSetupBlock)\n"

        let source = """
        extension \(typeName): SQLiteTableRepresentable {
            struct SQLiteRecord: Decodable, FetchableRecord {
                \(decodingSection)
                \(recordFieldsBlock)
            }

            static func loadModelsFromSQLiteRows(modelContext: SwiftData.ModelContext, database: GRDB.Database) throws {
                let records = try SQLiteRecord.fetchAll(database, sql: \"SELECT * FROM \(tableName)\")
                for record in records {
                    let model = try \(typeName)(record: record, modelContext: modelContext)
                    let id = record.id
                    var modelFetchDescriptor = FetchDescriptor<\(typeName)>(predicate: #Predicate {
                        $0.id == id
                    })
                    modelFetchDescriptor.fetchLimit = 1
                    let result = try modelContext.fetch(modelFetchDescriptor)
                    if let existingModel = result.first {
                        \(updateAssignmentsBlock)
                        try modelContext.save()
                    } else {
                        modelContext.insert(model)
                    }
                }
            }
            convenience init(record: SQLiteRecord, modelContext: SwiftData.ModelContext) throws {\(maybeFkBlock)
                self.init(
                \(initArgsBlock)
                )
            }
        }
        """

        let declaration = DeclSyntax(stringLiteral: source)
        guard let extensionDeclaration = declaration.as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [extensionDeclaration]
    }

    private static func collectProperties(from declaration: some DeclGroupSyntax) -> [PropertyInfo] {
        declaration.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                return nil
            }
            guard
                let binding = variable.bindings.first,
                let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                let typeAnnotation = binding.typeAnnotation
            else {
                return nil
            }

            let name = identifier.identifier.text
            let typeName = typeAnnotation.type.trimmedDescription
            let isArray = typeName.hasPrefix("[") || typeName.hasPrefix("Array<")
            let hasRelationshipAttribute = hasRelationshipAttribute(on: variable)
            let foreignKey = parseForeignKey(from: variable, typeName: typeName, isArray: isArray)
            let customColumnName: String?
            if foreignKey == nil {
                customColumnName = parseSQLiteColumn(from: variable)
            } else {
                customColumnName = nil
            }

            return PropertyInfo(
                name: name,
                typeName: typeName,
                isArray: isArray,
                hasRelationshipAttribute: hasRelationshipAttribute,
                foreignKey: foreignKey,
                customColumnName: customColumnName
            )
        }
    }

    private static func parseFirstInitializerParameters(from declaration: some DeclGroupSyntax) -> [InitializerParameterInfo] {
        guard
            let initializer = declaration.memberBlock.members
                .compactMap({ $0.decl.as(InitializerDeclSyntax.self) })
                .first
        else {
            return []
        }

        return initializer.signature.parameterClause.parameters.compactMap { parameter in
            let firstName = parameter.firstName.text
            let secondName = parameter.secondName?.text

            if firstName == "_", let secondName {
                return InitializerParameterInfo(argumentLabel: nil, localName: secondName)
            }

            if let secondName {
                return InitializerParameterInfo(argumentLabel: firstName, localName: secondName)
            }

            return InitializerParameterInfo(argumentLabel: firstName, localName: firstName)
        }
    }

    private static func buildInitializerArgument(label: String?, valueExpression: String) -> String {
        guard let label else {
            return valueExpression
        }
        return "\(label): \(valueExpression)"
    }

    private static func buildRecordFieldLines(from properties: [PropertyInfo]) -> [String] {
        properties.compactMap { property in
            if let foreignKey = property.foreignKey {
                return "var \(foreignKey.recordPropertyName): Int"
            }
            return "var \(property.name): \(property.typeName)"
        }
    }

    private static func recordFieldName(for property: PropertyInfo) -> String {
        if let fk = property.foreignKey {
            return fk.recordPropertyName
        }
        return property.name
    }

    private static func recordFieldDBColumn(for property: PropertyInfo) -> String {
        if let customName = property.customColumnName {
            return customName
        }
        if let fk = property.foreignKey {
            return fk.columnName
        }
        return property.name
    }

    private static func buildCodingKeysEnum(from properties: [PropertyInfo]) -> String? {
        let hasCustomColumn = properties.contains(where: { $0.customColumnName != nil })
        guard hasCustomColumn else { return nil }

        let caseLines = properties.map { property in
            let fieldName = recordFieldName(for: property)
            let columnName = recordFieldDBColumn(for: property)
            return "    case \(fieldName) = \"\(columnName)\""
        }

        return """
enum CodingKeys: String, CodingKey {
\(caseLines.joined(separator: "\n"))
}
"""
    }

    private static func parseTableName(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self), arguments.count == 1 else {
            return nil
        }
        guard let tableName = arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
            return nil
        }
        return tableName
    }

    private static func parseForeignKey(from variable: VariableDeclSyntax, typeName: String, isArray: Bool) -> ForeignKeyInfo? {
        if let explicitForeignKey = parseExplicitForeignKey(from: variable) {
            return explicitForeignKey
        }
        return inferForeignKeyFromRelationship(from: variable, typeName: typeName, isArray: isArray)
    }

    private static func parseExplicitForeignKey(from variable: VariableDeclSyntax) -> ForeignKeyInfo? {
        guard let attribute = variable.attributes.compactMap({ $0.as(AttributeSyntax.self) }).first(where: { $0.attributeName.trimmedDescription == "SQLiteForeignKey" }) else {
            return nil
        }
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self), arguments.count == 2 else {
            return nil
        }
        guard let columnName = arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
            return nil
        }
        guard let keyPathExpr = arguments.last?.expression.as(KeyPathExprSyntax.self) else {
            return nil
        }
        guard let typeName = keyPathExpr.root?.trimmedDescription else {
            return nil
        }
        guard let propertyName = keyPathExpr.components.first?.component.as(KeyPathPropertyComponentSyntax.self)?.declName.trimmedDescription else {
            return nil
        }
        return ForeignKeyInfo(
            columnName: columnName,
            recordPropertyName: columnName,
            typeName: typeName,
            propertyName: propertyName,
            keyPath: keyPathExpr.trimmedDescription
        )
    }

    private static func parseSQLiteColumn(from variable: VariableDeclSyntax) -> String? {
        guard let attribute = variable.attributes.compactMap({ $0.as(AttributeSyntax.self) }).first(where: { $0.attributeName.trimmedDescription == "SQLiteColumn" }) else {
            return nil
        }
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self), arguments.count == 1 else {
            return nil
        }
        return arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    }

    private static func inferForeignKeyFromRelationship(from variable: VariableDeclSyntax, typeName: String, isArray: Bool) -> ForeignKeyInfo? {
        guard !isArray else {
            return nil
        }
        guard hasRelationshipAttribute(on: variable) else {
            return nil
        }
        guard let normalizedTypeName = normalizeRelationshipTypeName(typeName) else {
            return nil
        }

        return ForeignKeyInfo(
            columnName: "\(normalizedTypeName.lowercased())_id",
            recordPropertyName: "\(normalizedTypeName.prefix(1).lowercased())\(normalizedTypeName.dropFirst())Id",
            typeName: normalizedTypeName,
            propertyName: "id",
            keyPath: "\\\(normalizedTypeName).id"
        )
    }

    private static func hasRelationshipAttribute(on variable: VariableDeclSyntax) -> Bool {
        variable.attributes
            .compactMap { $0.as(AttributeSyntax.self) }
            .contains { $0.attributeName.trimmedDescription == "Relationship" }
    }

    private static func normalizeRelationshipTypeName(_ typeName: String) -> String? {
        var normalizedTypeName = typeName.replacingOccurrences(of: " ", with: "")

        if normalizedTypeName.hasSuffix("?") || normalizedTypeName.hasSuffix("!") {
            normalizedTypeName.removeLast()
        }

        if normalizedTypeName.hasPrefix("Optional<") && normalizedTypeName.hasSuffix(">") {
            normalizedTypeName.removeFirst("Optional<".count)
            normalizedTypeName.removeLast()
        } else if normalizedTypeName.hasPrefix("Swift.Optional<") && normalizedTypeName.hasSuffix(">") {
            normalizedTypeName.removeFirst("Swift.Optional<".count)
            normalizedTypeName.removeLast()
        }

        if let lastComponent = normalizedTypeName.split(separator: ".").last {
            normalizedTypeName = String(lastComponent)
        }

        return normalizedTypeName.isEmpty ? nil : normalizedTypeName
    }
}


