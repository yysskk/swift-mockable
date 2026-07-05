import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler-plugin entry point that registers the macros provided by this module.
@main
struct MockablePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MockableMacro.self
    ]
}
