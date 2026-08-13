# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Support for `nonisolated` requirements of a global-actor-isolated protocol, such as `nonisolated var id: String { get }` on a `@MainActor` protocol. Swift infers the isolation of a witness from the requirement it satisfies, so the mock's witness was `nonisolated` while the state it reads was isolated, and the expansion failed to compile with "main actor-isolated property '_id' can not be referenced from a nonisolated context". A mock with such a requirement now keeps its tracking state behind `MockableLock`, and the members that requirement reaches are `nonisolated`, so tests can set handlers, read call counts, and call `resetMock()` without hopping to the actor — the same arrangement actor mocks already used.

### Fixed

- Mocking of a requirement whose parameter carries a specifier. A specifier is only valid in parameter position, but `consuming`, `borrowing`, `sending`, and `isolated` reached the mock's stored properties and handler types (`var consumeCallArgs: [consuming Payload] = []`), which failed to compile with "'consuming' may only be used on parameters". Specifiers are now stripped where the type is stored, alongside `inout`, which was handled by a separate rule. An ownership specifier also limits how often the witness may use its argument — a `consuming` one may be consumed once, a `borrowing` one not at all, while the mock uses each argument twice — so such a parameter is rebound to a local first, copying it when it was only lent.
- The write-back of an `inout` implicitly unwrapped optional (`func fill(_ value: inout Int!)`), which cast the handler's result with `as! Int!` and failed to compile with "using '!' is not allowed here". The write-back cast is now derived from the same normalized type as the storage it converts from, so the two cannot disagree; for this requirement it needs no cast at all.
- `@discardableResult` on a requirement is now carried onto the generated witness. Witnesses are built from the requirement's signature rather than by editing the requirement, so the attribute was dropped and every call site that discarded the mock's result warned about an unused result. Other attributes are still dropped deliberately: a deprecation marks the requirement, not the mock a test calls.
- Classification of the types in a protocol's inheritance clause. Every inherited type other than `Sendable`, `Actor`, `AnyObject`, and `AnyActor` was taken for a parent protocol with a generated mock of its own, so `protocol Token: Hashable` expanded to `class TokenMock: HashableMock` and failed with "cannot find type 'HashableMock' in scope", and a module-qualified conformance (`Swift.Sendable`) was mistaken for a parent as well as leaving the mock without its lock-backed storage. Inherited types are now classified: a protocol with no requirements to witness — including `Error`, and any of these spelled `Swift.`-qualified — is a conformance the mock satisfies as it stands; a standard-library protocol whose requirements the macro cannot witness (`Hashable`, `Codable`, `Identifiable`, and the like) is reported at the inheritance clause, with the suggestion to drop the conformance or satisfy it in an extension; a parent written with generic arguments (`Container<Int>`, or the qualified `SomeModule.Container<Int>`) is reported too, instead of expanding to an unparsable superclass. A protocol inheriting `Error` now also gets the `Sendable` storage model, which `Error` requires.
- The mock type name of a protocol whose name is escaped: `` protocol `Type` `` produced the invalid type name `` `Type`Mock `` and is now `TypeMock`.
- The diagnostic for an `init` requirement on an inheriting protocol fired for protocols whose mock does not subclass anything — an actor protocol, or one whose only inherited types are conformances — reporting a requirement that generates correctly. It is now raised only when the mock actually subclasses a parent mock.

- Mocking of requirements whose tracking identifiers coincide. Each requirement chose the identifier its own kind suggested — a method's name, an overload's name plus a disambiguating suffix, `init`, or `subscript` plus the index types — and those suggestions could collide across requirements even though each was unique among its own kind. A protocol declaring both `func load(_ item: Item)` (suffixed to `loadItem` because `load` is overloaded) and `func loadItem()` generated two `loadItemCallCount`, `loadItemCallArgs`, and `loadItemHandler` members, so the expansion failed to compile with "invalid redeclaration"; the same applied to a subscript or `init` overload whose suffixed identifier spelled out another requirement's name, and to a property of that name. Identifiers are now assigned across the whole protocol: a requirement tracked under a name it declares keeps it, and only a suggestion carrying a generated suffix gives way, by continuing to count (`loadItem2`). Identifiers are unchanged for a protocol whose requirements do not collide.

- Mocking of a requirement whose parameter the generated body cannot refer to as written. A wildcard parameter (`func handle(_: Event)`) names nothing, so the mock expanded to `handleCallArgs.append(_)` and failed to parse; the witness now gives it an internal name of its own (`func handle(_ param0: Event)`), which records and forwards the argument as usual. A parameter named with a keyword (`func value(for: Key)`, where the label doubles as the parameter's name) expanded to `valueCallArgs.append(for)` and failed to parse; such names are now escaped (`` `for` ``). Argument labels are untouched in both cases, so call sites are unaffected.
- Mocking of a requirement with a parameter named after something the generated body already uses. A parameter named `storage` or `_handler` shadowed the mock's own bindings — a `Sendable` mock of `func save(storage: Data)` recorded the storage struct instead of the argument — and a parameter named after a tracking member (`func fetch(fetchCallCount: Int)`) shadowed the member the body records into. The generated bindings now step aside, and tracking members are read through `self`, so the argument and the mock's own state stay distinct. A subscript index named `newValue` no longer collides with the setter's implicit `newValue` either: it previously passed the index as the assigned value, silently, and the setter now names its parameter explicitly.

- Mocking of a requirement declared in an `#else` clause. Member generation visits every clause of a conditional-compilation block, but the analyses that decide the mock's shape skipped clauses without a condition, so an `#else` requirement was mocked without the surrounding declarations it needs. A `static` requirement declared only in an `#else` clause referenced a `_staticStorage` that was never emitted ("cannot find `_staticStorage` in scope"); same-name requirements declared only in an `#else` clause were not recognized as overloads and generated duplicate `CallCount`/`CallArgs`/`Handler` members; and an `init` requirement declared only in an `#else` clause did not suppress the synthesized `init()` of a `public` or `package` mock, so the two collided. Requirements in sibling clauses now share one namespace, exactly as requirements in `#if`/`#elseif` clauses already did, so same-name requirements across the branches of one block are disambiguated with the usual overload suffixes.

## [1.12.0] - 2026-08-12

### Added

- A `condition:` argument on `@Mockable` that controls the `#if` guard around the generated mock: `.debug` (the default, matching the previous always-`#if DEBUG` behavior), `.custom("CONDITION")` for a custom compilation condition, and `.always` for no guard. This makes mocks usable in test-support modules built in the release configuration, SwiftUI previews, and UI-test host apps. The custom condition accepts a flag (`"MOCKING"`) or a compound compilation condition expression built from identifiers, `true`/`false`, `!`, `&&`, `||`, parentheses, and platform checks (`"DEBUG || UITESTS"`, `"os(iOS) && !RELEASE"`). Invalid arguments (non-literal values, interpolated strings, or unsupported condition constructs) emit compile-time diagnostics.
- A diagnostic for a requirement whose return type mentions a generic parameter inside a function type (`func makeSetter<T>() -> (T) -> Void`). The mock casts its erased handler result back to the declared return type, and Swift cannot convert between function types at runtime, so the requirement cannot be mocked; it now reports that instead of expanding to code that does not compile.
- A diagnostic for a requirement that takes a closure whose own parameters mention a generic parameter (`func observe<T>(_ handler: (T) -> Void)`). A closure's parameters are contravariant, so the argument cannot be forwarded to the erased handler. Erasing a closure's result is unaffected, so `func load<T>(_ make: () -> T)` is mocked normally.
- A diagnostic for a requirement whose name is not a plain identifier: an operator (`static func == (lhs: Self, rhs: Self) -> Bool`) or a method or property name that needs backtick escaping (`` func `repeat`() ``, `` var `default`: Int { get } ``). Generated members are named after the requirement, so these expanded to `==CallCount`, `` `repeat`CallCount ``, and `` _`default` `` and the build failed with parse errors inside the expansion; the unsupported name is now reported at the declaration instead.

### Fixed

- The lock-based subscript getter of a `Sendable`/actor mock acquired the storage lock twice — once to record the call and again to read the handler — so another thread could observe the recorded call before the handler was read, and reset the handler in between. It now records the call and reads the handler in a single `withLock`, matching the method witnesses.
- Mocking of overloaded subscripts whose parameter types produce the same identifier suffix. Two subscripts such as `subscript(key: String) -> Int` and `subscript(key: String) -> Bool` both generated `subscriptStringCallCount`/`subscriptStringHandler`, so the expansion failed to compile with duplicate members. Subscripts now use the same disambiguation ladder as functions — parameter types, then the return type and `async`/`throws` markers, then a deterministic source-order ordinal — so each overload gets distinct members (`subscriptStringIntHandler`, `subscriptStringBoolHandler`). A sole subscript keeps its previous suffix, so existing mocks are unaffected.
- Parenthesization of an erased closure nested in an optional. `(() -> T)?` erased to `() -> Any?` — a closure returning an optional — instead of `(() -> Any)?`, so a requirement such as `func load<T>(_ make: (() -> T)?)` did not compile. This applied to a closure keeping an attribute as well (`(@Sendable () -> T)?`), including one that mentions no generic parameter at all, such as a `(@Sendable () -> Int)?` parameter alongside a generic one.
- Type erasure for the remaining spellings that mention a generic parameter: a nested generic argument that is a tuple or a function type (`Box<(T, String)>`, `Callback<() -> T>`), an existential (`any Sequence<T>`), and a metatype (`T.Type`). Detection now walks the type instead of enumerating type kinds, so no spelling is missed. A generic return type spelled as a tuple (`(T, String)`) or an implicitly unwrapped optional (`T!`) is also cast back correctly; the latter previously produced `as! T!`, which Swift rejects.
- Type erasure for generic parameters mentioned through a nested generic argument (`Box<[T]>`), a module-qualified type (`MyModule.Box<T>`, `Swift.Array<T>`), or a type nested in a generic parameter (`T.Element`). These reached the mock's stored property and handler verbatim and failed to compile with "cannot find type 'T' in scope"; they are now erased to `Any` like every other type that mentions a generic parameter. Detection and erasure now share a single implementation, so a type is erased exactly when the generated method casts the handler's result back.
- Type erasure for generic parameters nested in a dictionary literal type. A requirement such as `func transform<T>(_ map: [String: T]) -> [String: T]` kept `[String: T]` verbatim in the mock's stored property and handler, which referenced the method-level generic parameter at class scope and failed to compile with "cannot find type 'T' in scope". The dictionary value is now erased in place (`[String: Any]`), and a dictionary whose key mentions a generic parameter is erased as a whole to `Any` because `Any` is not `Hashable`. The unsugared `Dictionary<String, T>` spelling was already handled.
- Mocking of a `throws(Never)` requirement, which cannot throw. The mock re-threw the handler's error as `Never` and failed to compile with "thrown expression type 'any Error' cannot be converted to error type 'Never'"; it now generates a non-throwing handler and calls it without `try`, keeping the `throws(Never)` signature. This covers methods, effectful properties and subscripts, `@autoclosure () throws(Never) -> T` parameters (evaluated without `try`), and function-type parameters. A throwing `@autoclosure` in a `throws(Never)` requirement is now reported as a diagnostic instead of expanding to code that does not compile.
- Mocking of a typed-throws requirement that takes a throwing `@autoclosure` parameter (`func compute(_ value: @autoclosure () throws -> Int) throws(ComputeError) -> Int`). The mock evaluates autoclosure arguments with `try` in its own body, which the typed-throws conversion did not cover, so the expansion failed to compile with "thrown expression type 'any Error' cannot be converted to error type 'ComputeError'". The body is now wrapped in a single `do`/`catch` that converts the autoclosure's error as well as the handler's. This applies to `init` requirements too.
- Mocking of a `throws(any Error)` requirement, which throws exactly what untyped `throws` does. The mock wrapped the handler call in `do { ... } catch { throw error as! any Error }`, whose forced cast emitted a "forced cast of 'any Error' to same type has no effect" warning in the consuming build; it now takes the untyped path with no re-throw. The bare `throws(Error)` spelling is treated the same way.

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

[Unreleased]: https://github.com/yysskk/swift-mockable/compare/1.12.0...HEAD
[1.12.0]: https://github.com/yysskk/swift-mockable/compare/1.11.1...1.12.0
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
