import Testing

import Mockable

// The test target never defines `MOCKABLE_ELSE_BRANCH`, so every `#else` branch below
// is the active one. Compiling these mocks proves the generated members of an `#else`
// clause are backed by the storage, tracking identifiers, and initializers the
// whole-protocol analyses are responsible for.

@Mockable
protocol ElseClauseStaticService {
    #if MOCKABLE_ELSE_BRANCH
    func unused()
    #else
    static func makeValue() -> Int
    #endif
}

@Mockable
protocol ElseClauseOverloadService {
    #if MOCKABLE_ELSE_BRANCH
    func unused()
    #else
    func fetch(id: Int) -> Int
    func fetch(name: String) -> Int
    #endif
}

@Mockable
public protocol ElseClauseInitService {
    #if MOCKABLE_ELSE_BRANCH
    func unused()
    #else
    init(name: String)
    #endif
}

@Suite("Else Clause Integration Tests")
struct ElseClauseTests {
    @Test("A static requirement declared in an #else clause records calls")
    func staticRequirementRecordsCalls() {
        let mock = ElseClauseStaticServiceMock()
        mock.resetMock()

        ElseClauseStaticServiceMock.makeValueHandler = { 42 }

        #expect(ElseClauseStaticServiceMock.makeValue() == 42)
        #expect(ElseClauseStaticServiceMock.makeValueCallCount == 1)

        mock.resetMock()
        #expect(ElseClauseStaticServiceMock.makeValueCallCount == 0)
        #expect(ElseClauseStaticServiceMock.makeValueHandler == nil)
    }

    @Test("Overloads declared in an #else clause track independently")
    func overloadsTrackIndependently() {
        let mock = ElseClauseOverloadServiceMock()

        mock.fetchIntHandler = { $0 * 2 }
        mock.fetchStringHandler = { $0.count }

        #expect(mock.fetch(id: 21) == 42)
        #expect(mock.fetch(name: "abc") == 3)
        #expect(mock.fetchIntCallCount == 1)
        #expect(mock.fetchStringCallCount == 1)
        #expect(mock.fetchIntCallArgs == [21])
        #expect(mock.fetchStringCallArgs == ["abc"])

        mock.resetMock()
        #expect(mock.fetchIntCallCount == 0)
        #expect(mock.fetchStringCallCount == 0)
    }

    @Test("An init requirement declared in an #else clause records its arguments")
    func initializerRecordsArguments() {
        let mock = ElseClauseInitServiceMock(name: "mock")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArgs == ["mock"])
    }
}
