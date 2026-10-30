import Foundation
import Testing

import Mockable

@Suite("_MockableLock Tests")
struct MockableLockTests {
    @Test("_MockableLock can be instantiated with initial value")
    func mockableLockCanBeInstantiated() {
        let lock = _MockableLock(42)
        let result = lock.withLock { $0 }
        #expect(result == 42)
    }

    @Test("_MockableLock withLock returns result")
    func mockableLockWithLockReturnsResult() {
        let lock = _MockableLock("initial")
        let result = lock.withLock { value -> String in
            value + " modified"
        }
        #expect(result == "initial modified")
    }

    @Test("_MockableLock withLock can mutate value")
    func mockableLockWithLockCanMutateValue() {
        let lock = _MockableLock(0)

        lock.withLock { value in
            value = 100
        }

        let result = lock.withLock { $0 }
        #expect(result == 100)
    }

    @Test("_MockableLock withLock can throw")
    func mockableLockWithLockCanThrow() {
        struct TestError: Error {}

        let lock = _MockableLock("value")

        #expect(throws: TestError.self) {
            try lock.withLock { _ in
                throw TestError()
            }
        }
    }

    @Test("_MockableLock is thread-safe")
    func mockableLockIsThreadSafe() async {
        let lock = _MockableLock(0)

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

    @Test("_MockableLock is Sendable")
    func mockableLockIsSendable() {
        let lock = _MockableLock("test")

        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let result = useSendable(lock)

        let value = result.withLock { $0 }
        #expect(value == "test")
    }

    @Test("_MockableLock with struct value")
    func mockableLockWithStructValue() {
        struct Counter {
            var count: Int = 0
            var name: String = ""
        }

        let lock = _MockableLock(Counter())

        lock.withLock { counter in
            counter.count = 10
            counter.name = "test"
        }

        let result = lock.withLock { $0 }
        #expect(result.count == 10)
        #expect(result.name == "test")
    }

    @Test("_MockableLock concurrent reads and writes")
    func mockableLockConcurrentReadsAndWrites() async {
        struct Storage {
            var items: [Int] = []
        }

        let lock = _MockableLock(Storage())

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    lock.withLock { storage in
                        storage.items.append(i)
                    }
                }
            }

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

    @Test("_MockableLock discardable result")
    func mockableLockDiscardableResult() {
        let lock = _MockableLock(0)

        lock.withLock { value in
            value = 42
        }

        let result = lock.withLock { $0 }
        #expect(result == 42)
    }
}
