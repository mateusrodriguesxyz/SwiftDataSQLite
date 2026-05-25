// The Swift Programming Language
// https://docs.swift.org/swift-book

@_exported import GRDB
import SwiftData
import SwiftUI
import Foundation

@attached(peer)
public macro SQLiteForeignKey(_ column: String, _ keyPath: AnyKeyPath) = #externalMacro(module: "SwiftDataSQLiteMacros", type: "SQLiteForeignKeyMacro")

@attached(extension, conformances: SQLiteTableRepresentable, names: named(SQLiteRecord), named(loadModelsFromSQLiteRows(modelContext:database:)), named(init(record:modelContext:)))
public macro SQLiteTable(_ table: String) = #externalMacro(module: "SwiftDataSQLiteMacros", type: "SQLiteTableMacro")

public protocol SQLiteTableRepresentable: PersistentModel {
	static func loadModelsFromSQLiteRows(modelContext: SwiftData.ModelContext, database: GRDB.Database) throws
}

extension View {
    public func modelContainer(for modelTypes: [any SQLiteTableRepresentable.Type], inMemory: Bool = false, sqliteDatabasePath: String) -> some View {
        modelContainer(for: modelTypes, inMemory: inMemory) { result in
            do {
                let modelContext = try result.get().mainContext
                try modelContext.loadFromSQLite(modelTypes, path: sqliteDatabasePath)
            } catch {
                print(error)
            }
        }
    }
}

extension ModelContext {
    package func loadFromSQLite(_ tableTypes: [any SQLiteTableRepresentable.Type], path: String) throws {
        let queue = try DatabaseQueue(path: path)
        try queue.read { database in
            for type in tableTypes {
                try _loadModelsFromSQLiteRows(type: type, database: database)
            }
        }
    }
    func _loadModelsFromSQLiteRows<T: SQLiteTableRepresentable>(type: T.Type, database: GRDB.Database) throws {
//        guard try fetchCount(FetchDescriptor(predicate: Predicate<T>.true)) == 0 else {
//            return
//        }
        try type.loadModelsFromSQLiteRows(modelContext: self, database: database)
    }
}
