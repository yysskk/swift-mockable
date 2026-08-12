import Testing

@testable import MockableMacros

@Suite("MockNaming Tests")
struct MockNamingTests {
    @Test("Fixed names match the generated-mock conventions")
    func fixedNames() {
        #expect(MockNaming.resetMethodName == "resetMock")
        #expect(MockNaming.instanceStorageName == "_storage")
        #expect(MockNaming.staticStorageName == "_staticStorage")
        #expect(MockNaming.storageTypeName == "Storage")
        #expect(MockNaming.staticStorageTypeName == "StaticStorage")
    }

    @Test("mockTypeName appends the Mock suffix")
    func mockTypeName() {
        #expect(MockNaming.mockTypeName(forProtocol: "UserService") == "UserServiceMock")
    }

    @Test("Tracking-member names derive from the requirement identifier")
    func trackingMemberNames() {
        #expect(MockNaming.callCount("fetch") == "fetchCallCount")
        #expect(MockNaming.callArgs("fetch") == "fetchCallArgs")
        #expect(MockNaming.handler("fetch") == "fetchHandler")
        #expect(MockNaming.setHandler("subscriptInt") == "subscriptIntSetHandler")
    }

    @Test("variableBacking prefixes an underscore")
    func variableBacking() {
        #expect(MockNaming.variableBacking("name") == "_name")
    }

    @Test("Subscript and initializer identifiers append the overload suffix")
    func overloadIdentifiers() {
        #expect(MockNaming.subscriptIdentifier(suffix: "Int") == "subscriptInt")
        #expect(MockNaming.subscriptIdentifier(suffix: "") == "subscript")
        #expect(MockNaming.initializerIdentifier(suffix: "String") == "initString")
        #expect(MockNaming.initializerIdentifier(suffix: "") == "init")
    }

    @Test("storageName selects the static or instance storage property")
    func storageName() {
        #expect(MockNaming.storageName(isTypeMember: true) == "_staticStorage")
        #expect(MockNaming.storageName(isTypeMember: false) == "_storage")
    }
}
