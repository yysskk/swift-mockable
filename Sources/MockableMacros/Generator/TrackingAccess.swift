import SwiftSyntax

/// How a witness reaches the tracking state of one requirement.
///
/// A requirement's tracking slots live either as plain stored properties on the mock
/// or as fields of a storage struct behind `MockableLock` (see `StorageModel`). The
/// two differ only in how a witness records a call, reads a handler, and reads or
/// writes a backing slot, so those operations are expressed here once, and every
/// witness generator — methods, subscripts, initializers, and properties — builds a
/// single body from them instead of one per storage model.
enum TrackingAccess {
    /// Plain stored properties on the mock, read and written directly.
    case direct
    /// Fields of the storage struct behind the lock property `storageName`
    /// (`_storage` or `_staticStorage`), reached through one `withLock` per witness so
    /// that a call is recorded and its handler read atomically, and the handler is
    /// invoked outside the lock.
    case lockBacked(storageName: String)

    /// The storage model the tracking slots are declared under.
    var model: StorageModel {
        switch self {
        case .direct:
            return .direct
        case .lockBacked:
            return .lockBacked
        }
    }

    /// The handler a witness invokes, together with the statements that bind it.
    struct HandlerBinding {
        /// The statements run before the handler is used: the recording assignments on
        /// direct access, or the single `withLock` that records the call and reads the
        /// handler on lock-backed access.
        let statements: [CodeBlockItemSyntax]
        /// The pattern that follows `guard let` or `if let`: `_handler = fooHandler` on
        /// direct access, where the binding itself reads the stored property, or just
        /// `_handler` on lock-backed access, where `statements` already bound it.
        let pattern: String
    }

    /// The mock members a witness body refers to by name, so `WitnessNames` can keep a
    /// requirement's parameters from shadowing them: the tracking members themselves on
    /// direct access, or the lock property on lock-backed access.
    func referencedMembers(_ trackingMembers: [String]) -> [String] {
        switch self {
        case .direct:
            return trackingMembers
        case .lockBacked(let storageName):
            return [storageName]
        }
    }

    /// The statements that record a call: increment `identifier`'s call count and, when
    /// `recordedArguments` is given, append it to the captured arguments. On lock-backed
    /// access both happen inside one `withLock`.
    func recordingStatements(
        identifier: String,
        recordedArguments: ExprSyntax?,
        names: MockGenerator.WitnessNames
    ) -> [CodeBlockItemSyntax] {
        switch self {
        case .direct:
            return recordingLines(identifier: identifier, recordedArguments: recordedArguments, prefix: names.memberPrefix)
                .map { CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: $0))) }

        case .lockBacked(let storageName):
            let body = recordingLines(identifier: identifier, recordedArguments: recordedArguments, prefix: "\(names.storage).")
                .map { "    \($0)" }
                .joined(separator: "\n")
            return [CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: """
            \(names.member(storageName)).withLock { \(names.storage) in
            \(body)
            }
            """)))]
        }
    }

    /// Records a call and binds the requirement's handler for the witness to invoke.
    /// `handlerType` is the handler slot's type, e.g. `(@Sendable (Int) -> String)?`.
    func handlerBinding(
        identifier: String,
        recordedArguments: ExprSyntax?,
        handlerType: TypeSyntax,
        names: MockGenerator.WitnessNames
    ) -> HandlerBinding {
        switch self {
        case .direct:
            return HandlerBinding(
                statements: recordingStatements(identifier: identifier, recordedArguments: recordedArguments, names: names),
                pattern: "\(names.handler) = \(names.member(MockNaming.handler(identifier)))"
            )

        case .lockBacked(let storageName):
            let recording = recordingLines(identifier: identifier, recordedArguments: recordedArguments, prefix: "\(names.storage).")
                .map { "    \($0)" }
                .joined(separator: "\n")
            let statement = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
            let \(names.handler) = \(names.member(storageName)).withLock { \(names.storage) -> \(handlerType.trimmedDescription) in
            \(recording)
                return \(names.storage).\(MockNaming.handler(identifier))
            }
            """)))
            return HandlerBinding(statements: [statement], pattern: names.handler)
        }
    }

    /// The `if let` pattern that reads the handler `handlerName` without recording
    /// anything, for a witness that only forwards (a subscript setter).
    func handlerReadPattern(handlerName: String, names: MockGenerator.WitnessNames) -> String {
        switch self {
        case .direct:
            return "\(names.handler) = \(names.member(handlerName))"
        case .lockBacked(let storageName):
            return "\(names.handler) = \(names.member(storageName)).withLock({ $0.\(handlerName) })"
        }
    }

    /// The expression that reads a tracking slot, e.g. `_name!` or
    /// `_storage.withLock { $0._name! }`. `storedExpression` is the slot as read from
    /// inside its storage, including any force unwrap.
    func read(_ storedExpression: String) -> String {
        switch self {
        case .direct:
            return storedExpression
        case .lockBacked(let storageName):
            return "\(storageName).withLock { $0.\(storedExpression) }"
        }
    }

    /// The statement that assigns `value` to the tracking slot `storedName`, e.g.
    /// `_name = newValue` or `_storage.withLock { $0._name = newValue }`.
    func write(_ storedName: String, _ value: String) -> String {
        switch self {
        case .direct:
            return "\(storedName) = \(value)"
        case .lockBacked(let storageName):
            return "\(storageName).withLock { $0.\(storedName) = \(value) }"
        }
    }

    /// The recording assignments as source lines, each slot addressed with `prefix`
    /// (`self.`/`Self.` when a parameter shadows the member, or `storage.` inside the
    /// lock).
    private func recordingLines(identifier: String, recordedArguments: ExprSyntax?, prefix: String) -> [String] {
        var lines = ["\(prefix)\(MockNaming.callCount(identifier)) += 1"]
        if let recordedArguments {
            lines.append("\(prefix)\(MockNaming.callArguments(identifier)).append(\(recordedArguments))")
        }
        return lines
    }
}

extension MockGenerator {
    /// How the witnesses of a requirement in `scope` reach its tracking state: through
    /// the lock for `Sendable`/actor mocks and for type members, directly otherwise.
    func trackingAccess(for scope: MemberScope) -> TrackingAccess {
        guard usesLockBasedStorage(for: scope) else {
            return .direct
        }
        return .lockBacked(storageName: MockNaming.storageName(for: scope))
    }
}
