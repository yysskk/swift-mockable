# ``Mockable``

A Swift macro that generates protocol mocks for tests.

## Overview

`swift-mockable` provides the ``Mockable()`` macro that automatically generates mock implementations of protocols. Generated mocks include call tracking, configurable handlers, and property stubs.

- Generated mocks are emitted inside `#if DEBUG`.
- Generated names follow a predictable convention (`<name>CallCount`, `<name>CallArgs`, `<name>Handler`).
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
- ``Mockable()``

### Advanced

- <doc:AdvancedUsage>

### Supporting Types

- ``MockableLock``
