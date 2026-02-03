// Re-export Mutex for Sendable mock support (macOS 15.0+/iOS 18.0+)
#if canImport(Synchronization)
@_exported import Synchronization
#endif

/// A macro that generates a mock class for a protocol.
///
/// When applied to a protocol, this macro generates a `<ProtocolName>Mock` class
/// that implements the protocol with configurable behavior for testing.
///
/// ## Usage
///
/// ```swift
/// @Mockable
/// protocol UserService {
///     func fetchUser(id: Int) async throws -> User
///     var currentUser: User? { get }
/// }
/// ```
///
/// This generates a `UserServiceMock` class with:
/// - Handlers for each method that can be configured
/// - Call tracking for verification
/// - Property stubs
///
/// ## Parameters
///
/// - `legacyLock`: When `true`, forces the use of `LegacyLock` instead of `Mutex`
///   for thread-safe storage. Use this when your project needs to support iOS 17 or earlier
///   while still conforming to `Sendable` or `Actor` protocols. Default is `false`.
///
/// ## Example with legacyLock
///
/// ```swift
/// @Mockable(legacyLock: true)
/// protocol MyService: Sendable {
///     func fetch() async -> Data
/// }
/// ```
///
@attached(peer, names: suffixed(Mock))
public macro Mockable(legacyLock: Bool = false) = #externalMacro(module: "MockableMacros", type: "MockableMacro")
