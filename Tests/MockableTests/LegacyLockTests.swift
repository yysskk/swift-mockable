import Foundation
import Testing

import Mockable

// MARK: - LegacyLock Unit Tests

@Suite("LegacyLock Tests")
struct LegacyLockTests {
    @Test("LegacyLock can be instantiated with initial value")
    func legacyLockCanBeInstantiated() {
        let lock = LegacyLock(42)
        let result = lock.withLock { $0 }
        #expect(result == 42)
    }

    @Test("LegacyLock withLock returns result")
    func legacyLockWithLockReturnsResult() {
        let lock = LegacyLock("initial")
        let result = lock.withLock { value -> String in
            value + " modified"
        }
        #expect(result == "initial modified")
    }

    @Test("LegacyLock withLock can mutate value")
    func legacyLockWithLockCanMutateValue() {
        let lock = LegacyLock(0)

        lock.withLock { value in
            value = 100
        }

        let result = lock.withLock { $0 }
        #expect(result == 100)
    }

    @Test("LegacyLock withLock can throw")
    func legacyLockWithLockCanThrow() {
        struct TestError: Error {}

        let lock = LegacyLock("value")

        #expect(throws: TestError.self) {
            try lock.withLock { _ in
                throw TestError()
            }
        }
    }

    @Test("LegacyLock is thread-safe")
    func legacyLockIsThreadSafe() async {
        let lock = LegacyLock(0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    lock.withLock { value in
                        value += 1
                    }
                }
            }
        }

        let result = lock.withLock { $0 }
        #expect(result == 1000)
    }

    @Test("LegacyLock is Sendable")
    func legacyLockIsSendable() {
        let lock = LegacyLock("test")

        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let result = useSendable(lock)

        let value = result.withLock { $0 }
        #expect(value == "test")
    }

    @Test("LegacyLock with struct value")
    func legacyLockWithStructValue() {
        struct Counter {
            var count: Int = 0
            var name: String = ""
        }

        let lock = LegacyLock(Counter())

        lock.withLock { counter in
            counter.count = 10
            counter.name = "test"
        }

        let result = lock.withLock { $0 }
        #expect(result.count == 10)
        #expect(result.name == "test")
    }

    @Test("LegacyLock concurrent reads and writes")
    func legacyLockConcurrentReadsAndWrites() async {
        struct Storage {
            var items: [Int] = []
        }

        let lock = LegacyLock(Storage())

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<100 {
                group.addTask {
                    lock.withLock { storage in
                        storage.items.append(i)
                    }
                }
            }
            // Readers
            for _ in 0..<50 {
                group.addTask {
                    _ = lock.withLock { storage in
                        storage.items.count
                    }
                }
            }
        }

        let count = lock.withLock { $0.items.count }
        #expect(count == 100)
    }

    @Test("LegacyLock discardable result")
    func legacyLockDiscardableResult() {
        let lock = LegacyLock(0)

        // Should compile without warning due to @discardableResult
        lock.withLock { value in
            value = 42
        }

        let result = lock.withLock { $0 }
        #expect(result == 42)
    }
}
