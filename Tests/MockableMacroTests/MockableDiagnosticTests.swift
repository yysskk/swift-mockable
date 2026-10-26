import SwiftDiagnostics
import Testing

@testable import MockableMacros

@Suite("Mockable Diagnostic Tests")
struct MockableDiagnosticTests {
    @Test("Every diagnostic is an error")
    func severityAndDomain() {
        let diagnostics: [MockableDiagnostic] = [
            .notAProtocol,
            .unsupportedMember(member: "struct Nested {}"),
            .invalidMacroArgument(.unlabeled),
            .unsupportedAutoclosureEffect(parameter: "value", uncoveredEffects: ["throws"], inSubscript: false),
            .unsupportedMemberName(name: "==", isOperator: true),
            .unsupportedInitializer,
            .unsupportedAssociatedType(name: "Item"),
            .unsupportedInheritedType(name: "Hashable", reason: .requirementsCannotBeWitnessed),
            .unsupportedGenericReturn(requirement: "makeSetter", returnType: "(T) -> Void"),
            .unsupportedGenericParameter(requirement: "observe", parameter: "handler", parameterType: "(T) -> Void"),
        ]

        for diagnostic in diagnostics {
            #expect(diagnostic.severity == .error)
        }
    }

    @Test("Each case has its own stable identifier in the MockableMacro domain")
    func identifiers() {
        func id(_ identifier: String) -> MessageID {
            MessageID(domain: "MockableMacro", id: identifier)
        }

        #expect(MockableDiagnostic.notAProtocol.diagnosticID == id("notAProtocol"))
        #expect(MockableDiagnostic.unsupportedMember(member: "").diagnosticID == id("unsupportedMember"))
        #expect(MockableDiagnostic.invalidMacroArgument(.customEmpty).diagnosticID == id("invalidMacroArgument"))
        #expect(
            MockableDiagnostic.unsupportedAutoclosureEffect(parameter: "", uncoveredEffects: [], inSubscript: true)
                .diagnosticID == id("unsupportedAutoclosureEffect")
        )
        #expect(MockableDiagnostic.unsupportedMemberName(name: "", isOperator: false).diagnosticID == id("unsupportedMemberName"))
        #expect(MockableDiagnostic.unsupportedInitializer.diagnosticID == id("unsupportedInitializer"))
        #expect(MockableDiagnostic.unsupportedAssociatedType(name: "").diagnosticID == id("unsupportedAssociatedType"))
        #expect(
            MockableDiagnostic.unsupportedInheritedType(name: "", reason: .parameterized).diagnosticID == id("unsupportedInheritedType")
        )
        #expect(MockableDiagnostic.unsupportedGenericReturn(requirement: "", returnType: "").diagnosticID == id("unsupportedGenericReturn"))
        #expect(
            MockableDiagnostic.unsupportedGenericParameter(requirement: "", parameter: "", parameterType: "").diagnosticID == id("unsupportedGenericParameter")
        )
    }

    @Test("An autoclosure diagnostic names the effects the requirement lacks")
    func autoclosureEffects() {
        let one = MockableDiagnostic.unsupportedAutoclosureEffect(
            parameter: "value",
            uncoveredEffects: ["throws"],
            inSubscript: false
        )
        #expect(one.message == "Cannot mock @autoclosure parameter 'value': the mock evaluates autoclosure arguments when called, so the requirement must be declared 'throws'")

        let both = MockableDiagnostic.unsupportedAutoclosureEffect(
            parameter: "value",
            uncoveredEffects: ["throws", "async"],
            inSubscript: false
        )
        #expect(both.message == "Cannot mock @autoclosure parameter 'value': the mock evaluates autoclosure arguments when called, so the requirement must be declared 'throws' and 'async'")

        let subscriptCase = MockableDiagnostic.unsupportedAutoclosureEffect(
            parameter: "key",
            uncoveredEffects: ["async"],
            inSubscript: true
        )
        #expect(subscriptCase.message == "Cannot mock @autoclosure parameter 'key': effectful autoclosures are not supported in subscript requirements")
    }

    @Test("A member-name diagnostic distinguishes operators from escaped names")
    func memberNames() {
        #expect(
            MockableDiagnostic.unsupportedMemberName(name: "==", isOperator: true).message
                == "Cannot mock '==': operator requirements are not supported"
        )
        #expect(
            MockableDiagnostic.unsupportedMemberName(name: "`repeat`", isOperator: false).message
                == "Cannot mock '`repeat`': only requirements whose name is a plain identifier can be mocked"
        )
    }

    @Test("An inherited-type diagnostic explains each reason")
    func inheritedTypes() {
        let unwitnessable = MockableDiagnostic.unsupportedInheritedType(name: "Hashable", reason: .requirementsCannotBeWitnessed)
        #expect(unwitnessable.message.hasPrefix("'Hashable' declares requirements @Mockable cannot generate witnesses for"))

        let parameterized = MockableDiagnostic.unsupportedInheritedType(name: "Container<Int>", reason: .parameterized)
        #expect(parameterized.message.hasPrefix("'Container<Int>' is a parent protocol written with generic arguments"))
    }

    @Test("An argument diagnostic is prefixed and names the offending argument")
    func argumentProblems() {
        #expect(
            MockableDiagnostic.invalidMacroArgument(.unexpectedLabel("flag")).message
                == "Invalid @Mockable argument: unexpected argument label 'flag'; the only supported argument is 'condition:'"
        )
        #expect(
            MockableDiagnostic.invalidMacroArgument(.customUnparsable("DEBUG &&")).message
                == "Invalid @Mockable argument: 'DEBUG &&' is not a valid compilation condition expression"
        )
        #expect(
            MockableDiagnostic.invalidMacroArgument(.duplicateCondition).message
                == "Invalid @Mockable argument: duplicate 'condition' argument"
        )
    }
}
