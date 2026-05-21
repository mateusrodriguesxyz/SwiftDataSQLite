// swift-tools-version: 6.0

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftDataSQLite",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .macCatalyst(.v18)],
    products: [
        .library(
            name: "SwiftDataSQLite",
            targets: ["SwiftDataSQLite"]
        ),
        .executable(
            name: "SwiftDataSQLiteClient",
            targets: ["SwiftDataSQLiteClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0"),
    ],
    targets: [
        .macro(
            name: "SwiftDataSQLiteMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(
            name: "SwiftDataSQLite",
            dependencies: [
                "SwiftDataSQLiteMacros",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "SwiftDataSQLiteClient",
            dependencies: ["SwiftDataSQLite"],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
