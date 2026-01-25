import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

func assertMacroExpansionForTesting(
    _ originalSource: String,
    expandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    macros: [String: Macro.Type],
    conformsTo conformances: [TypeSyntax] = [],
    testModuleName: String = "TestModule",
    testFileName: String = "test.swift",
    indentationWidth: Trivia = .spaces(4),
    fileID: StaticString = #fileID, filePath: StaticString = #filePath,
    file: StaticString = #file, line: UInt = #line, column: UInt = #column
) {
    assertMacroExpansion(
        originalSource, expandedSource: expandedSource,
        diagnostics: diagnostics,
        macroSpecs: macros.mapValues { value in
            return MacroSpec(type: value, conformances: conformances)
        },
        testModuleName: testModuleName, testFileName: testFileName,
        indentationWidth: indentationWidth
    ) { spec in
        Issue.record(
            .init(rawValue: spec.message),
            sourceLocation: .init(
                fileID: String(describing: fileID), filePath: String(describing: filePath),
                line: Int(line), column: Int(column)
            )
        )
    }
}
