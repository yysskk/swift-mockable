# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A diagnostic for a requirement whose return type mentions a generic parameter inside a function type (`func makeSetter<T>() -> (T) -> Void`). The mock casts its erased handler result back to the declared return type, and Swift cannot convert between function types at runtime, so the requirement cannot be mocked; it now reports that instead of expanding to code that does not compile.
- A diagnostic for a requirement that takes a closure whose own parameters mention a generic parameter (`func observe<T>(_ handler: (T) -> Void)`). A closure's parameters are contravariant, so the argument cannot be forwarded to the erased handler. Erasing a closure's result is unaffected, so `func load<T>(_ make: () -> T)` is mocked normally.

### Fixed

- Parenthesization of an erased closure nested in an optional. `(() -> T)?` erased to `() -> Any?` — a closure returning an optional — instead of `(() -> Any)?`, so a requirement such as `func load<T>(_ make: (() -> T)?)` did not compile.
- Type erasure for the remaining spellings that mention a generic parameter: a nested generic argument that is a tuple or a function type (`Box<(T, String)>`, `Callback<() -> T>`), an existential (`any Sequence<T>`), and a metatype (`T.Type`). Detection now walks the type instead of enumerating type kinds, so no spelling is missed. A generic return type spelled as a tuple (`(T, String)`) or an implicitly unwrapped optional (`T!`) is also cast back correctly; the latter previously produced `as! T!`, which Swift rejects.
- Type erasure for generic parameters mentioned through a nested generic argument (`Box<[T]>`), a module-qualified type (`MyModule.Box<T>`, `Swift.Array<T>`), or a type nested in a generic parameter (`T.Element`). These reached the mock's stored property and handler verbatim and failed to compile with "cannot find type 'T' in scope"; they are now erased to `Any` like every other type that mentions a generic parameter. Detection and erasure now share a single implementation, so a type is erased exactly when the generated method casts the handler's result back.
- Type erasure for generic parameters nested in a dictionary literal type. A requirement such as `func transform<T>(_ map: [String: T]) -> [String: T]` kept `[String: T]` verbatim in the mock's stored property and handler, which referenced the method-level generic parameter at class scope and failed to compile with "cannot find type 'T' in scope". The dictionary value is now erased in place (`[String: Any]`), and a dictionary whose key mentions a generic parameter is erased as a whole to `Any` because `Any` is not `Hashable`. The unsugared `Dictionary<String, T>` spelling was already handled.

### Added

- A `condition:` argument on `@Mockable` that controls the `#if` guard around the generated mock: `.debug` (the default, matching the previous always-`#if DEBUG` behavior), `.custom("CONDITION")` for a custom compilation condition, and `.always` for no guard. This makes mocks usable in test-support modules built in the release configuration, SwiftUI previews, and UI-test host apps. The custom condition accepts a flag (`"MOCKING"`) or a compound compilation condition expression built from identifiers, `true`/`false`, `!`, `&&`, `||`, parentheses, and platform checks (`"DEBUG || UITESTS"`, `"os(iOS) && !RELEASE"`). Invalid arguments (non-literal values, interpolated strings, or unsupported condition constructs) emit compile-time diagnostics.

## [1.11.1] - 2026-07-14

### Changed

- Widened the accepted swift-syntax versions from a single major to `509.0.0..<604.0.0` in every manifest, so adding swift-mockable no longer causes a dependency-resolution conflict in projects whose other packages pin a different swift-syntax major.

## [1.11.0] - 2026-07-13

### Added

- Official visionOS support: the package now declares `.visionOS(.v1)`, and `MockableLock` prefers `Mutex` (`Synchronization`) on visionOS 2.0+, falling back to the `NSLock`-based lock on visionOS 1.0.
- Support for `init` requirements: `@Mockable` now generates a recording `required init` (`initCallCount`, `initCallArgs`) instead of failing with a diagnostic, unlocking the `init(configuration:)` pattern. `Sendable` and `actor` mocks record behind `MockableLock`, and child mocks inherit a parent's `init` requirement through the inherited `required init`. Declaring a new `init` requirement directly on an inheriting protocol is not yet supported and emits a diagnostic.

### Changed

- Child mocks now inherit their parent mock's initializers instead of synthesizing their own parameterless `init()`. Construction is unchanged for existing mocks, and this lets a child mock inherit a parent's `required init`.

## [1.10.0] - 2026-07-04

### Added

- Support for typed throws (`throws(MyError)`, SE-0413) on methods, properties, and subscripts. The mock keeps the typed-throws signature and re-throws the untyped-throwing handler's error as the declared type.
- Support for effectful read-only property accessors (`get async`, `get throws`, `get async throws`), mocked with a handler and a call counter.
- Support for effectful read-only subscripts (`subscript(...) -> V { get async throws }`).
- Support for `rethrows` methods: the mock keeps the `rethrows` signature and generates a non-throwing handler that receives the throwing closure arguments.
- Evaluation of `@autoclosure` parameters when recording calls: the argument is evaluated once per call and its value is recorded and forwarded to the handler.
- Handling of non-escaping closure parameters: the closure is forwarded to the handler and excluded from `CallArgs` (it cannot be stored), while the call is still counted.

### Fixed

- Colliding overload identifier suffixes (e.g. nested generics that sanitize identically) are disambiguated with a deterministic ordinal.

### Changed

- CI now builds and tests on macOS in addition to Linux, and cancels superseded PR runs.

## [1.9.1] - 2026-06-09

### Added

- Individual-parameter handlers for multi-argument members, so handlers can be written as `{ a, b in ... }`.

## [1.9.0] - 2026-06-04

### Added

- Default return values for unset handlers with `Optional` and collection return types.

### Fixed

- Module-qualified stdlib types (`Swift.Optional`, `Swift.Array`, etc.) are recognized in default-return detection.

## [1.8.0] - 2026-04-06

### Added

- `@MainActor` protocol support.
- `typealias` declaration support.
- `open` mock classes for public protocols.
- Handling of parenthesized `@escaping` parameter types.

## [1.7.0] - 2026-03-09

### Added

- Static function and static property support.
- Diagnostics for unsupported `@Mockable` input, preserving `#elseif`/`#else` clauses.

### Changed

- Unified lock strategy via `MockableLock`, replacing conditional compilation.

## [1.6.0] - 2026-03-06

### Added

- Protocol inheritance support.
- `inout` parameter support.
- Variadic parameter support.

### Changed

- `Sendable` mock classes use `@unchecked Sendable` instead of `final`.

## [1.5.0] - 2026-02-04

### Added

- Overloaded method support, including overloads that differ only by return type or effects.
- Access-level-aware mock generation.
- `#if DEBUG` conditional compilation support inside protocols.
- Swift 5.9 / 5.10 backward compatibility and iOS 17 support for `Sendable`/`Actor` mocks.

## [1.4.0] - 2026-01-26

### Added

- Subscript support (including unique suffixes for subscript overloads).
- Associated type support.
- `Actor` protocol support.
- `resetMock()` method.

## [1.3.1] - 2026-01-22

### Fixed

- `@escaping` attribute is stripped from generated mock property types.

## [1.3.0] - 2026-01-22

### Added

- `Sendable` protocol support with thread-safe mock generation.
- Simplified handler syntax for zero-argument methods.

## [1.2.0] - 2026-01-21

### Added

- Generic method support.

## [1.1.0] - 2026-01-20

### Changed

- Generated mock naming changed from a prefix to a suffix (`<Protocol>Mock`).

## [1.0.0] - 2026-01-19

### Added

- Initial release of the `@Mockable` macro.

[Unreleased]: https://github.com/yysskk/swift-mockable/compare/1.11.1...HEAD
[1.11.1]: https://github.com/yysskk/swift-mockable/compare/1.11.0...1.11.1
[1.11.0]: https://github.com/yysskk/swift-mockable/compare/1.10.0...1.11.0
[1.10.0]: https://github.com/yysskk/swift-mockable/compare/1.9.1...1.10.0
[1.9.1]: https://github.com/yysskk/swift-mockable/compare/1.9.0...1.9.1
[1.9.0]: https://github.com/yysskk/swift-mockable/compare/1.8.0...1.9.0
[1.8.0]: https://github.com/yysskk/swift-mockable/compare/1.7.0...1.8.0
[1.7.0]: https://github.com/yysskk/swift-mockable/compare/1.6.0...1.7.0
[1.6.0]: https://github.com/yysskk/swift-mockable/compare/1.5.0...1.6.0
[1.5.0]: https://github.com/yysskk/swift-mockable/compare/1.4.0...1.5.0
[1.4.0]: https://github.com/yysskk/swift-mockable/compare/1.3.1...1.4.0
[1.3.1]: https://github.com/yysskk/swift-mockable/compare/1.3.0...1.3.1
[1.3.0]: https://github.com/yysskk/swift-mockable/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/yysskk/swift-mockable/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/yysskk/swift-mockable/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/yysskk/swift-mockable/releases/tag/1.0.0
