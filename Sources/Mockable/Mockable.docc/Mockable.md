# ``Mockable``

A Swift macro that generates protocol mocks for tests.

## Overview

`swift-mockable` provides the ``Mockable(condition:)`` macro that automatically generates mock implementations of protocols. Generated mocks include call tracking, configurable handlers, and property stubs.

- Generated mocks are emitted inside `#if DEBUG` by default; pass a ``MockCompilationCondition`` to guard them with a custom flag, or to emit them unconditionally.
- Generated names follow a predictable convention (`<name>CallCount`, `<name>CallArguments`, `<name>Handler`).
- The call history (`<name>CallCount`, `<name>CallArguments`) is read-only outside the mock; handlers and properties are writable for setup. A requirement without arguments to record has a `CallCount` only.
- `resetMock()` is generated to clear all tracking state.

```swift
import Mockable

@Mockable
protocol UserService {
    func fetchUser(id: Int) async throws -> User
    var currentUser: User? { get }
}

let mock = UserServiceMock()

mock.fetchUserHandler = { id in
    User(id: id, name: "Test User")
}

let user = try await mock.fetchUser(id: 42)
assert(mock.fetchUserCallCount == 1)
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``Mockable(condition:)``
- ``MockCompilationCondition``

### Advanced

- <doc:AdvancedUsage>

### Migration

- <doc:MigratingTo3>
- <doc:MigratingTo3_1>
