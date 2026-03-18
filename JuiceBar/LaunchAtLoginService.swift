import Foundation
import ServiceManagement

struct LaunchAtLoginState {
    var isEnabled: Bool
    var note: String?
}

enum LaunchAtLoginError: LocalizedError {
    case unavailableOutsideAppBundle

    var errorDescription: String? {
        switch self {
        case .unavailableOutsideAppBundle:
            return "Launch at Login is available when Juice Bar runs from an app bundle."
        }
    }
}

struct LaunchAtLoginService {
    private let service = SMAppService.mainApp

    var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func currentState() -> LaunchAtLoginState {
        guard isAvailable else {
            return LaunchAtLoginState(isEnabled: false, note: LaunchAtLoginError.unavailableOutsideAppBundle.localizedDescription)
        }

        switch service.status {
        case .enabled:
            return LaunchAtLoginState(isEnabled: true, note: nil)
        case .requiresApproval:
            return LaunchAtLoginState(isEnabled: false, note: "Enable Juice Bar in System Settings > Login Items after turning it on.")
        case .notRegistered:
            return LaunchAtLoginState(isEnabled: false, note: nil)
        case .notFound:
            return LaunchAtLoginState(isEnabled: false, note: "Launch at Login is unavailable for this build.")
        @unknown default:
            return LaunchAtLoginState(isEnabled: false, note: "Launch at Login reported an unknown state.")
        }
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState {
        guard isAvailable else {
            throw LaunchAtLoginError.unavailableOutsideAppBundle
        }

        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }

        return currentState()
    }
}
