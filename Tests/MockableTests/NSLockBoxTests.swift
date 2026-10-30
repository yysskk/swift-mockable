import Foundation
import Testing

@testable import Mockable

// MARK: - NSLockBox Unit Tests

@Suite("NSLockBox Tests")
struct NSLockBoxTests {
    @Test("NSLockBox can be instantiated with initial value")
    func legacyLockCanBeInstantiated() {
        let lock = NSLockBox(42)
        let result = lock.withLock { $0 }
        #expect(result == 42)
    }

    @Test("NSLockBox withLock returns result")
    func legacyLockWithLockReturnsResult() {
        let lock = NSLockBox("initial")
        let result = lock.withLock { value -> String in
            value + " modified"
        }
        #expect(result == "initial modified")
    }

    @Test("NSLockBox withLock can mutate value")
    func legacyLockWithLockCanMutateValue() {
        let lock = NSLockBox(0)

        lock.withLock { value in
            value = 100
        }

        let result = lock.withLock { $0 }
        #expect(result == 100)
    }

    @Test("NSLockBox withLock can throw")
    func legacyLockWithLockCanThrow() {
        struct TestError: Error {}

        let lock = NSLockBox("value")

        #expect(throws: TestError.self) {
            try lock.withLock { _ in
                throw TestError()
            }
        }
    }

    @Test("NSLockBox is thread-safe")
    func legacyLockIsThreadSafe() async {
        let lock = NSLockBox(0)

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

    @Test("NSLockBox is Sendable")
    func legacyLockIsSendable() {
        let lock = NSLockBox("test")

        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let result = useSendable(lock)

        let value = result.withLock { $0 }
        #expect(value == "test")
    }

    @Test("NSLockBox with struct value")
    func legacyLockWithStructValue() {
        struct Counter {
            var count: Int = 0
            var name: String = ""
        }

        let lock = NSLockBox(Counter())

        lock.withLock { counter in
            counter.count = 10
            counter.name = "test"
        }

        let result = lock.withLock { $0 }
        #expect(result.count == 10)
        #expect(result.name == "test")
    }

    @Test("NSLockBox concurrent reads and writes")
    func legacyLockConcurrentReadsAndWrites() async {
        struct Storage {
            var items: [Int] = []
        }

        let lock = NSLockBox(Storage())

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

    @Test("NSLockBox discardable result")
    func legacyLockDiscardableResult() {
        let lock = NSLockBox(0)

        // Should compile without warning due to @discardableResult
        lock.withLock { value in
            value = 42
        }

        let result = lock.withLock { $0 }
        #expect(result == 42)
    }
}
