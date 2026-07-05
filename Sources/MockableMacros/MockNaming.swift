/// Single source of truth for the identifier conventions used in generated mocks.
///
/// Centralizing these names keeps the generator files consistent and makes the
/// naming scheme easy to audit or change in one place. The values are pinned by
/// the macro-expansion tests, so any change here is reflected across every mock.
enum MockNaming {
    /// The generated reset method name (`resetMock`).
    static let resetMethodName = "resetMock"

    /// The instance-level lock-backed storage property name (`_storage`).
    static let instanceStorageName = "_storage"

    /// The static lock-backed storage property name (`_staticStorage`).
    static let staticStorageName = "_staticStorage"

    /// The instance storage struct type name (`Storage`).
    static let storageTypeName = "Storage"

    /// The static storage struct type name (`StaticStorage`).
    static let staticStorageTypeName = "StaticStorage"

    /// The generated mock type name for a protocol, e.g. `UserService` -> `UserServiceMock`.
    static func mockTypeName(forProtocol protocolName: String) -> String {
        "\(protocolName)Mock"
    }

    /// The call-count tracking property, e.g. `fetch` -> `fetchCallCount`.
    static func callCount(_ identifier: String) -> String {
        "\(identifier)CallCount"
    }

    /// The captured-arguments property, e.g. `fetch` -> `fetchCallArgs`.
    static func callArgs(_ identifier: String) -> String {
        "\(identifier)CallArgs"
    }

    /// The configurable handler property, e.g. `fetch` -> `fetchHandler`.
    static func handler(_ identifier: String) -> String {
        "\(identifier)Handler"
    }

    /// The configurable setter handler property (get-set subscripts), e.g. `subscriptInt` -> `subscriptIntSetHandler`.
    static func setHandler(_ identifier: String) -> String {
        "\(identifier)SetHandler"
    }

    /// The backing storage property for a mocked variable, e.g. `name` -> `_name`.
    static func variableBacking(_ varName: String) -> String {
        "_\(varName)"
    }

    /// The base identifier for a subscript with the given overload suffix, e.g. `subscriptInt`.
    static func subscriptIdentifier(suffix: String) -> String {
        "subscript\(suffix)"
    }

    /// The lock-backed storage property name for instance or static members.
    static func storageName(isTypeMember: Bool) -> String {
        isTypeMember ? staticStorageName : instanceStorageName
    }
}
