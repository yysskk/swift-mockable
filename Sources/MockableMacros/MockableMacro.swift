import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// The implementation of the `@Mockable` attached peer macro.
///
/// Applied to a protocol, it generates a `<Protocol>Mock` class (wrapped in `#if DEBUG`
/// by default; the `condition:` argument selects a different guard, see
/// ``CompilationCondition``) that conforms to the protocol and records calls, captures
/// arguments, and exposes a configurable handler for every requirement. The protocol's
/// shape drives the output: `Sendable`/`Actor` conformances select a lock-backed storage
/// model, an inherited protocol produces a subclassing mock, and anything the mock cannot
/// satisfy is reported as a diagnostic (see ``ProtocolValidator``) instead of generating
/// invalid code.
public struct MockableMacro: PeerMacro {
    /// Generates the mock class peer for a `@Mockable` protocol.
    ///
    /// Returns an empty array (emitting diagnostics) when the declaration is not a
    /// protocol, when the macro's arguments are invalid, or when a member cannot be
    /// mocked.
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(.notAProtocol, at: node)
            return []
        }

        // The protocol-level shape drives both validation and code generation.
        let shape = ProtocolShape(protocolDecl)

        // `nil` means the arguments were invalid and diagnostics were emitted; the
        // protocol is still validated so all problems surface in one pass.
        let condition = CompilationCondition.parse(from: node, in: context)
        let findings = ProtocolValidator.findings(in: shape, members: protocolDecl.memberBlock.members)
        for finding in findings {
            context.diagnose(finding.diagnostic, at: finding.node)
        }
        guard let condition, findings.isEmpty else {
            return []
        }

        // Diagnostics above read the protocol as written; generation reads it with every
        // requirement's parameters renamed to something the generated bodies can refer
        // to (see `ParameterNameNormalizer`). Normalizing once, here, keeps every later
        // pass looking at the same nodes.
        let members = ParameterNameNormalizer().visit(protocolDecl.memberBlock.members)

        let mockClass = MockGenerator(shape: shape, members: members).generate()

        return [condition.wrapping(mockClass)]
    }
}
