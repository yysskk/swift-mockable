import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

/// Which of a requirement's attributes the generated witness keeps.
@Suite("Witness Attribute Macro Tests")
struct WitnessAttributeMacroTests {
    let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("@discardableResult is carried onto the witness")
    func discardableResultIsCarried() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                @discardableResult
                func run() -> Int
            }
            """,
            expandedSource: """
            protocol Service {
                @discardableResult
                func run() -> Int
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var runCallCount: Int = 0
                @available(*, deprecated, message: "run records no arguments; use runCallCount instead.")
                var runCallArguments: [()] {
                    Array(repeating: (), count: runCallCount)
                }
                var runHandler: (() -> Int)? = nil
                @discardableResult
                func run() -> Int {
                    runCallCount += 1
                    guard let _handler = runHandler else {
                        fatalError("\\(Self.self).runHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    runCallCount = 0
                    runHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A deprecation on the requirement is not carried onto the witness")
    func deprecationIsNotCarried() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                @available(*, deprecated)
                func run() -> Int
            }
            """,
            expandedSource: """
            protocol Service {
                @available(*, deprecated)
                func run() -> Int
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var runCallCount: Int = 0
                @available(*, deprecated, message: "run records no arguments; use runCallCount instead.")
                var runCallArguments: [()] {
                    Array(repeating: (), count: runCallCount)
                }
                var runHandler: (() -> Int)? = nil
                func run() -> Int {
                    runCallCount += 1
                    guard let _handler = runHandler else {
                        fatalError("\\(Self.self).runHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    runCallCount = 0
                    runHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Only the carried attributes survive filtering")
    func filtersAttributes() {
        let decl: DeclSyntax = """
        @discardableResult @available(*, deprecated) @inlinable
        func run() -> Int
        """
        let attributes = decl.as(FunctionDeclSyntax.self)!.attributes
        let carried = MockGenerator.witnessAttributes(of: attributes)
        #expect(carried.map(\.trimmedDescription) == ["@discardableResult"])
    }
}
