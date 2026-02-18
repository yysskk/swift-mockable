import SwiftSyntax

// MARK: - Storage Strategy

enum StorageStrategy {
    case direct
    case mutex
    case legacyLock

    var isLockBased: Bool {
        switch self {
        case .direct:
            return false
        case .mutex, .legacyLock:
            return true
        }
    }

    var lockTypeName: String? {
        switch self {
        case .direct:
            return nil
        case .mutex:
            return "Mutex"
        case .legacyLock:
            return "LegacyLock"
        }
    }
}
