import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Tracking Access Tests")
struct TrackingAccessTests {
    private let parameters: FunctionParameterListSyntax = {
        let decl: DeclSyntax = "func fetch(id: Int)"
        return decl.as(FunctionDeclSyntax.self)!.signature.parameterClause.parameters
    }()

    private func names(memberNames: [String] = []) -> MockGenerator.WitnessNames {
        MockGenerator.WitnessNames(parameters: parameters, memberNames: memberNames)
    }

    private func rendered(_ statements: [CodeBlockItemSyntax]) -> [String] {
        statements.map(\.trimmedDescription)
    }

    // MARK: - Storage model

    @Test("Each access reports the storage model its slots are declared under")
    func storageModel() {
        #expect(TrackingAccess.direct.model == .direct)
        #expect(TrackingAccess.lockBacked(storageName: "_storage").model == .lockBacked)
    }

    @Test("Direct access refers to the tracking members; lock-backed access to the lock")
    func referencedMembers() {
        let members = ["fetchCallCount", "fetchHandler"]
        #expect(TrackingAccess.direct.referencedMembers(members) == members)
        #expect(TrackingAccess.lockBacked(storageName: "_storage").referencedMembers(members) == ["_storage"])
    }

    // MARK: - Recording

    @Test("Direct access records with one assignment per slot")
    func directRecording() {
        let statements = TrackingAccess.direct.recordingStatements(
            identifier: "fetch",
            recordedArguments: "id",
            names: names()
        )
        #expect(rendered(statements) == ["fetchCallCount += 1", "fetchCallArgs.append(id)"])
    }

    @Test("Direct access qualifies members a parameter shadows")
    func directRecordingQualifiesShadowedMembers() {
        let statements = TrackingAccess.direct.recordingStatements(
            identifier: "fetch",
            recordedArguments: "id",
            names: names(memberNames: ["id"])
        )
        #expect(rendered(statements) == ["self.fetchCallCount += 1", "self.fetchCallArgs.append(id)"])
    }

    @Test("Lock-backed access records inside a single withLock")
    func lockBackedRecording() {
        let statements = TrackingAccess.lockBacked(storageName: "_storage").recordingStatements(
            identifier: "fetch",
            recordedArguments: "id",
            names: names()
        )
        #expect(rendered(statements) == ["""
        _storage.withLock { storage in
            storage.fetchCallCount += 1
            storage.fetchCallArgs.append(id)
        }
        """])
    }

    @Test("A requirement without arguments records only its call count")
    func recordingWithoutArguments() {
        let direct = TrackingAccess.direct.recordingStatements(identifier: "token", recordedArguments: nil, names: names())
        #expect(rendered(direct) == ["tokenCallCount += 1"])

        let locked = TrackingAccess.lockBacked(storageName: "_storage").recordingStatements(
            identifier: "token",
            recordedArguments: nil,
            names: names()
        )
        #expect(rendered(locked) == ["""
        _storage.withLock { storage in
            storage.tokenCallCount += 1
        }
        """])
    }

    // MARK: - Handler binding

    @Test("Direct access records first and binds the handler in the guard pattern")
    func directHandlerBinding() {
        let binding = TrackingAccess.direct.handlerBinding(
            identifier: "fetch",
            recordedArguments: "id",
            handlerType: "(@Sendable (Int) -> String)?",
            names: names()
        )
        #expect(rendered(binding.statements) == ["fetchCallCount += 1", "fetchCallArgs.append(id)"])
        #expect(binding.pattern == "_handler = fetchHandler")
    }

    @Test("Lock-backed access records and reads the handler in one withLock, then binds it by name")
    func lockBackedHandlerBinding() {
        let binding = TrackingAccess.lockBacked(storageName: "_staticStorage").handlerBinding(
            identifier: "fetch",
            recordedArguments: "id",
            handlerType: "(@Sendable (Int) -> String)?",
            names: names()
        )
        #expect(rendered(binding.statements) == ["""
        let _handler = _staticStorage.withLock { storage -> (@Sendable (Int) -> String)? in
            storage.fetchCallCount += 1
            storage.fetchCallArgs.append(id)
            return storage.fetchHandler
        }
        """])
        #expect(binding.pattern == "_handler")
    }

    @Test("A handler is read without recording for a witness that only forwards")
    func handlerReadPattern() {
        #expect(
            TrackingAccess.direct.handlerReadPattern(handlerName: "subscriptIntSetHandler", names: names())
                == "_handler = subscriptIntSetHandler"
        )
        #expect(
            TrackingAccess.lockBacked(storageName: "_storage")
                .handlerReadPattern(handlerName: "subscriptIntSetHandler", names: names())
                == "_handler = _storage.withLock({ $0.subscriptIntSetHandler })"
        )
    }

    // MARK: - Backing slots

    @Test("A backing slot is read and written directly or through the lock")
    func backingSlotAccess() {
        #expect(TrackingAccess.direct.read("_name!") == "_name!")
        #expect(TrackingAccess.direct.write("_name", "newValue") == "_name = newValue")

        let locked = TrackingAccess.lockBacked(storageName: "_storage")
        #expect(locked.read("_name!") == "_storage.withLock { $0._name! }")
        #expect(locked.write("_name", "newValue") == "_storage.withLock { $0._name = newValue }")
    }

    // MARK: - Selection

    @Test("The generator selects lock-backed access for Sendable mocks and type members")
    func accessSelection() throws {
        func generator(ofProtocol source: String) throws -> MockGenerator {
            let decl: DeclSyntax = "\(raw: source)"
            let protocolDecl = try #require(decl.as(ProtocolDeclSyntax.self))
            return MockGenerator(shape: ProtocolShape(protocolDecl), members: protocolDecl.memberBlock.members)
        }

        let plain = try generator(ofProtocol: "protocol Service {}")
        guard case .direct = plain.trackingAccess(for: .instance) else {
            Issue.record("expected direct access for an instance member of a plain mock")
            return
        }
        guard case .lockBacked(let staticStorage) = plain.trackingAccess(for: .type) else {
            Issue.record("expected lock-backed access for a type member")
            return
        }
        #expect(staticStorage == "_staticStorage")

        let sendable = try generator(ofProtocol: "protocol Service: Sendable {}")
        guard case .lockBacked(let storage) = sendable.trackingAccess(for: .instance) else {
            Issue.record("expected lock-backed access for an instance member of a Sendable mock")
            return
        }
        #expect(storage == "_storage")
    }
}
