import SwiftSyntax

// MARK: - Storage Strategy

enum StorageStrategy {
    case direct
    case mockableLock

    var isLockBased: Bool {
        switch self {
        case .direct:
            return false
        case .mockableLock:
            return true
        }
    }

    var lockTypeName: String? {
        switch self {
        case .direct:
            return nil
        case .mockableLock:
            return "MockableLock"
        }
    }
}
