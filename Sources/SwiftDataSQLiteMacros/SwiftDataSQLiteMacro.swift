import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct SQLiteTableMacro: ExtensionMacro {
    
    private struct ForeignKeyInfo {
        let columnName: String
        let typeName: String
        let propertyName: String
        let keyPath: String
    }

    private struct PropertyInfo {
        let name: String
        let typeName: String
        let isArray: Bool
        let foreignKey: ForeignKeyInfo?
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

        let initProperties = properties.filter { !$0.isArray }

        var fkSetupLines: [String] = []
        var initArgumentLines: [String] = []

        for property in initProperties {
            if let foreignKey = property.foreignKey {
                let fkVarName = "\(property.name)ForeignKeyValue"
                let descriptorVarName = "\(property.name)FetchDescriptor"
                let relatedVarName = "\(property.name)"
                fkSetupLines.append("""
                let \(fkVarName) = __sqliteValue(row, \"\(foreignKey.columnName)\", \(foreignKey.keyPath))
                var \(descriptorVarName) = FetchDescriptor<\(foreignKey.typeName)>(predicate: #Predicate { $0.\(foreignKey.propertyName) == \(fkVarName) })
                \(descriptorVarName).fetchLimit = 1
                let \(relatedVarName) = try modelContext.fetch(\(descriptorVarName))[0]
                """)
                initArgumentLines.append("\(property.name): \(relatedVarName)")
            } else {
                initArgumentLines.append("\(property.name): row[\"\(property.name)\"]")
            }
        }

        let initArgsBlock = initArgumentLines.joined(separator: ",\n")
        let fkSetupBlock = fkSetupLines.joined(separator: "\n")
        let maybeFkBlock = fkSetupBlock.isEmpty ? "" : "\n\(fkSetupBlock)\n"

        let source = """
        extension \(typeName): SQLiteTableRepresentable {
            static func loadModelsFromSQLiteRows(modelContext: SwiftData.ModelContext, database: GRDB.Database) throws {
                try Row.fetchCursor(database, sql: \"SELECT * FROM \(tableName)\").forEach { row in
                    let model = try \(typeName)(row: row, modelContext: modelContext)
                    modelContext.insert(model)
                }
            }
            convenience init(row: GRDB.Row, modelContext: SwiftData.ModelContext) throws {\(maybeFkBlock)
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
            let foreignKey = parseForeignKey(from: variable)

            return PropertyInfo(name: name, typeName: typeName, isArray: isArray, foreignKey: foreignKey)
        }
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

    private static func parseForeignKey(from variable: VariableDeclSyntax) -> ForeignKeyInfo? {
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
            typeName: typeName,
            propertyName: propertyName,
            keyPath: keyPathExpr.trimmedDescription
        )
        return nil
    }
}


