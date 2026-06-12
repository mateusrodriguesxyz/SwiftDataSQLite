import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftDataSQLitePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SQLiteTableMacro.self,
        SQLiteForeignKeyMacro.self,
        SQLiteColumnMacro.self,
    ]
}
