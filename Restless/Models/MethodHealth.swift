import Foundation

// MARK: - Awake Method

/// Represents which sleep-prevention method is actively being used.
enum AwakeMethod: String, CustomStringConvertible {
    case caffeinate
    case iokitAssertion
    case userActivityOnly
    case none

    var description: String {
        switch self {
        case .caffeinate: return "caffeinate"
        case .iokitAssertion: return "IOKit Assertion"
        case .userActivityOnly: return "User Activity Assertion"
        case .none: return "None"
        }
    }
}

// MARK: - Method Status

/// Tracks the health/status of a manager's prevention methods.
enum MethodStatus: CustomStringConvertible {
    case healthy(method: AwakeMethod)
    case degraded(method: AwakeMethod, reason: String)
    case failed(reason: String)
    case inactive

    var description: String {
        switch self {
        case .healthy(let method):
            return "Healthy (\(method))"
        case .degraded(let method, let reason):
            return "\(method) (\(reason))"
        case .failed(let reason):
            return "Failed: \(reason)"
        case .inactive:
            return "Inactive"
        }
    }

    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }

    var isDegraded: Bool {
        if case .degraded = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
