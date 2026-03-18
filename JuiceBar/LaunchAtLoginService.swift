import Foundation
import ServiceManagement

enum LaunchAtLoginStatus {
    case disabled
    case enabled
    case requiresApproval
    case hiddenForUnsignedBuild
    case unavailableOutsideAppBundle
    case unavailableForBuild
    case unknown
}

struct LaunchAtLoginState {
    var status: LaunchAtLoginStatus
    var note: String?

    var isVisible: Bool {
        status != .hiddenForUnsignedBuild
    }

    var isControllable: Bool {
        switch status {
        case .disabled, .enabled, .requiresApproval:
            return true
        case .hiddenForUnsignedBuild, .unavailableOutsideAppBundle, .unavailableForBuild, .unknown:
            return false
        }
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var toggleValue: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .hiddenForUnsignedBuild, .unavailableOutsideAppBundle, .unavailableForBuild, .unknown:
            return false
        }
    }

    var statusText: String {
        switch status {
        case .disabled:
            return "Off"
        case .enabled:
            return "On"
        case .requiresApproval:
            return "Pending Approval"
        case .hiddenForUnsignedBuild:
            return ""
        case .unavailableOutsideAppBundle, .unavailableForBuild:
            return "Unavailable"
        case .unknown:
            return "Unknown"
        }
    }
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

    var isCodeSignedBundle: Bool {
        let codeSignatureURL = Bundle.main.bundleURL.appending(path: "Contents/_CodeSignature/CodeResources")
        return FileManager.default.fileExists(atPath: codeSignatureURL.path)
    }

    func currentState() -> LaunchAtLoginState {
        guard isAvailable else {
            return LaunchAtLoginState(
                status: .unavailableOutsideAppBundle,
                note: LaunchAtLoginError.unavailableOutsideAppBundle.localizedDescription
            )
        }

        guard isCodeSignedBundle else {
            return LaunchAtLoginState(status: .hiddenForUnsignedBuild, note: nil)
        }

        switch service.status {
        case .enabled:
            return LaunchAtLoginState(status: .enabled, note: "Juice Bar will launch automatically when you sign in.")
        case .requiresApproval:
            return LaunchAtLoginState(
                status: .requiresApproval,
                note: "Approval required in System Settings > General > Login Items. Juice Bar will not launch automatically until you allow it."
            )
        case .notRegistered:
            return LaunchAtLoginState(status: .disabled, note: "Juice Bar will not launch automatically when you sign in.")
        case .notFound:
            return LaunchAtLoginState(
                status: .unavailableForBuild,
                note: "Launch at Login is unavailable for this build."
            )
        @unknown default:
            return LaunchAtLoginState(
                status: .unknown,
                note: "Launch at Login reported an unknown state."
            )
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
