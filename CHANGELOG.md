# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

[Unreleased]: https://github.com/yysskk/swift-mockable/compare/1.9.1...HEAD
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
