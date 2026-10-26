// swift-tools-version: 6.2

import CompilerPluginSupport
import Foundation
import PackageDescription

let package = Package(
    name: "swift-mockable",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
        .macCatalyst(.v13),
    ],
    products: [
        .library(
            name: "Mockable",
            targets: ["Mockable"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.0.0"..<"605.0.0"),
    ],
    targets: [
        .macro(
            name: "MockableMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Mockable",
            dependencies: ["MockableMacros"]
        ),
        .testTarget(
            name: "MockableTests",
            dependencies: ["Mockable"],
            swiftSettings: [
                // Exercises @Mockable(condition: .custom(...)) end to end; the runtime
                // tests reference a mock that only exists when this flag is defined.
                .define("MOCKABLE_RUNTIME_TEST_CONDITION")
            ]
        ),
        .testTarget(
            name: "MockableMacroTests",
            dependencies: [
                "MockableMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)

// The DocC plugin only builds the documentation site (see
// .github/workflows/deploy-docs.yml and CONTRIBUTING.md). It is added to the
// package only when asked for, so a package that depends on Mockable does not
// resolve and fetch it as well.
if ProcessInfo.processInfo.environment["MOCKABLE_ENABLE_DOCC"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.5.0")
    )
}
