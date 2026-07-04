import Foundation
import Testing

import Mockable

struct CollisionFoo: Equatable {}
struct CollisionFooArray: Equatable {}

// `[CollisionFoo]` and `CollisionFooArray` both sanitize to the same suffix
// (`...CollisionFooArray`), so the two overloads previously produced duplicate,
// non-compiling members. They must now generate distinct handlers.
@Mockable
protocol CollidingOverloadService {
    func handle(_ value: [CollisionFoo]) -> Int
    func handle(_ value: CollisionFooArray) -> Int
}

@Suite("Overload Suffix Collision Tests")
struct OverloadSuffixCollisionTests {
    @Test("Colliding overloads route to independent handlers and call counts")
    func collidingOverloadsRouteIndependently() {
        let mock = CollidingOverloadServiceMock()
        mock.handleCollisionFooArrayIntHandler = { _ in 1 }
        mock.handleCollisionFooArrayInt2Handler = { _ in 2 }

        let arrayResult = mock.handle([CollisionFoo()])
        let structResult = mock.handle(CollisionFooArray())

        #expect(arrayResult == 1)
        #expect(structResult == 2)
        #expect(mock.handleCollisionFooArrayIntCallCount == 1)
        #expect(mock.handleCollisionFooArrayInt2CallCount == 1)
        #expect(mock.handleCollisionFooArrayIntCallArgs == [[CollisionFoo()]])
        #expect(mock.handleCollisionFooArrayInt2CallArgs == [CollisionFooArray()])
    }

    @Test("resetMock clears both colliding overloads")
    func resetMockClearsBothOverloads() {
        let mock = CollidingOverloadServiceMock()
        mock.handleCollisionFooArrayIntHandler = { _ in 1 }
        mock.handleCollisionFooArrayInt2Handler = { _ in 2 }
        _ = mock.handle([CollisionFoo()])
        _ = mock.handle(CollisionFooArray())

        mock.resetMock()

        #expect(mock.handleCollisionFooArrayIntCallCount == 0)
        #expect(mock.handleCollisionFooArrayInt2CallCount == 0)
        #expect(mock.handleCollisionFooArrayIntHandler == nil)
        #expect(mock.handleCollisionFooArrayInt2Handler == nil)
    }
}
