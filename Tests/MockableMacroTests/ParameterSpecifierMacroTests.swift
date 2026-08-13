import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

/// Parameters carrying a specifier. A specifier is only valid in parameter position, so
/// the mock's stored properties and handler types drop it; an ownership specifier also
/// limits how often the witness may use the argument.
@Suite("Parameter Specifier Macro Tests")
struct ParameterSpecifierMacroTests {
    let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("A consuming parameter is stored without its specifier and used once")
    func consumingParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func consume(_ item: consuming Payload)
            }
            """,
            expandedSource: """
            protocol Service {
                func consume(_ item: consuming Payload)
            }

            #if DEBUG
            class ServiceMock: Service {
                var consumeCallCount: Int = 0
                var consumeCallArgs: [Payload] = []
                var consumeHandler: (@Sendable (Payload) -> Void)? = nil
                func consume(_ item: consuming Payload) {
                    let item = item
                    consumeCallCount += 1
                    consumeCallArgs.append(item)
                    if let _handler = consumeHandler {
                        _handler(item)
                    }
                }
                func resetMock() {
                    consumeCallCount = 0
                    consumeCallArgs = []
                    consumeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A borrowing parameter is copied before it is recorded")
    func borrowingParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func inspect(_ item: borrowing Payload)
            }
            """,
            expandedSource: """
            protocol Service {
                func inspect(_ item: borrowing Payload)
            }

            #if DEBUG
            class ServiceMock: Service {
                var inspectCallCount: Int = 0
                var inspectCallArgs: [Payload] = []
                var inspectHandler: (@Sendable (Payload) -> Void)? = nil
                func inspect(_ item: borrowing Payload) {
                    let item = copy item
                    inspectCallCount += 1
                    inspectCallArgs.append(item)
                    if let _handler = inspectHandler {
                        _handler(item)
                    }
                }
                func resetMock() {
                    inspectCallCount = 0
                    inspectCallArgs = []
                    inspectHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A sending parameter keeps its specifier only in the witness signature")
    func sendingParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func send(_ item: sending Payload)
            }
            """,
            expandedSource: """
            protocol Service {
                func send(_ item: sending Payload)
            }

            #if DEBUG
            class ServiceMock: Service {
                var sendCallCount: Int = 0
                var sendCallArgs: [Payload] = []
                var sendHandler: (@Sendable (Payload) -> Void)? = nil
                func send(_ item: sending Payload) {
                    sendCallCount += 1
                    sendCallArgs.append(item)
                    if let _handler = sendHandler {
                        _handler(item)
                    }
                }
                func resetMock() {
                    sendCallCount = 0
                    sendCallArgs = []
                    sendHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("An implicitly unwrapped optional inout argument is written back without a cast")
    func implicitlyUnwrappedOptionalInOut() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func fill(_ value: inout Int!)
            }
            """,
            expandedSource: """
            protocol Service {
                func fill(_ value: inout Int!)
            }

            #if DEBUG
            class ServiceMock: Service {
                var fillCallCount: Int = 0
                var fillCallArgs: [Int?] = []
                var fillHandler: (@Sendable (Int?) -> Int?)? = nil
                func fill(_ value: inout Int!) {
                    fillCallCount += 1
                    fillCallArgs.append(value)
                    if let _handler = fillHandler {
                        let _writeBack = _handler(value)
                        value = _writeBack
                    }
                }
                func resetMock() {
                    fillCallCount = 0
                    fillCallArgs = []
                    fillHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
