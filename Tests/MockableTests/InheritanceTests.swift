import Testing

@testable import Mockable

@Suite("Protocol Inheritance Tests")
struct InheritanceTests {
    @Test("Child mock inherits parent mock members")
    func childMockInheritance() {
        let mock = ChildServiceMock()

        // Set up parent protocol members
        mock._baseName = "test"
        mock.baseMethodHandler = { "base result" }

        // Set up child protocol members
        mock.childMethodHandler = { 42 }

        // Verify parent members work
        #expect(mock.baseName == "test")
        #expect(mock.baseMethod() == "base result")
        #expect(mock.baseMethodCallCount == 1)

        // Verify child members work
        #expect(mock.childMethod() == 42)
        #expect(mock.childMethodCallCount == 1)
    }

    @Test("Child mock can be used as parent type")
    func childMockAsParentType() {
        let mock = ChildServiceMock()
        mock.baseMethodHandler = { "value" }
        mock._baseName = "name"

        let baseService: BaseService = mock
        #expect(baseService.baseMethod() == "value")
        #expect(baseService.baseName == "name")
    }

    @Test("Child mock can be used as child type")
    func childMockAsChildType() {
        let mock = ChildServiceMock()
        mock.baseMethodHandler = { "base" }
        mock._baseName = "name"
        mock.childMethodHandler = { 99 }

        let childService: ChildService = mock
        #expect(childService.baseMethod() == "base")
        #expect(childService.childMethod() == 99)
    }

    @Test("resetMock resets both parent and child members")
    func resetMockResetsAll() {
        let mock = ChildServiceMock()
        mock._baseName = "test"
        mock.baseMethodHandler = { "result" }
        mock.childMethodHandler = { 1 }

        _ = mock.baseMethod()
        _ = mock.childMethod()

        #expect(mock.baseMethodCallCount == 1)
        #expect(mock.childMethodCallCount == 1)

        mock.resetMock()

        #expect(mock.baseMethodCallCount == 0)
        #expect(mock.baseMethodCallArgs.isEmpty)
        #expect(mock.baseMethodHandler == nil)
        #expect(mock._baseName == nil)
        #expect(mock.childMethodCallCount == 0)
        #expect(mock.childMethodCallArgs.isEmpty)
        #expect(mock.childMethodHandler == nil)
    }

    @Test("ChildServiceMock is subclass of BaseServiceMock")
    func childMockIsSubclass() {
        let mock = ChildServiceMock()
        #expect(mock is BaseServiceMock)
    }
}
