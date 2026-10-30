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
                private(set) var consumeCallCount: Int = 0
                private(set) var consumeCallArguments: [Payload] = []
                var consumeHandler: ((Payload) -> Void)? = nil
                func consume(_ item: consuming Payload) {
                    let item = item
                    consumeCallCount += 1
                    consumeCallArguments.append(item)
                    if let _handler = consumeHandler {
                        _handler(item)
                    }
                }
                func resetMock() {
                    consumeCallCount = 0
                    consumeCallArguments = []
                    consumeHandler = nil
                }
                class func resetMock() {
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
                private(set) var inspectCallCount: Int = 0
                private(set) var inspectCallArguments: [Payload] = []
                var inspectHandler: ((Payload) -> Void)? = nil
                func inspect(_ item: borrowing Payload) {
                    let item = copy item
                    inspectCallCount += 1
                    inspectCallArguments.append(item)
                    if let _handler = inspectHandler {
                        _handler(item)
                    }
                }
                func resetMock() {
                    inspectCallCount = 0
                    inspectCallArguments = []
                    inspectHandler = nil
                }
                class func resetMock() {
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
                private(set) var sendCallCount: Int = 0
                private(set) var sendCallArguments: [Payload] = []
                var sendHandler: ((Payload) -> Void)? = nil
                func send(_ item: sending Payload) {
                    sendCallCount += 1
                    sendCallArguments.append(item)
                    if let _handler = sendHandler {
                        _handler(item)
                    }
                }
                func resetMock() {
                    sendCallCount = 0
                    sendCallArguments = []
                    sendHandler = nil
                }
                class func resetMock() {
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
                private(set) var fillCallCount: Int = 0
                private(set) var fillCallArguments: [Int?] = []
                var fillHandler: ((Int?) -> Int?)? = nil
                func fill(_ value: inout Int!) {
                    fillCallCount += 1
                    fillCallArguments.append(value)
                    if let _handler = fillHandler {
                        let _writeBack = _handler(value)
                        value = _writeBack
                    }
                }
                func resetMock() {
                    fillCallCount = 0
                    fillCallArguments = []
                    fillHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
