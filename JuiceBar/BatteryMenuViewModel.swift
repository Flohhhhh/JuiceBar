import AppKit
import Combine
import Foundation

@MainActor
final class BatteryMenuViewModel: ObservableObject {
    private let batteryService: BatteryService
    private let launchAtLoginService: LaunchAtLoginService

    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    @Published private(set) var batteryState = BatteryState(
        hasBattery: false,
        percentage: nil,
        isCharging: false,
        isFull: false,
        powerSource: .unknown,
        timeRemainingMinutes: nil
    )
    @Published private(set) var launchAtLoginState = LaunchAtLoginState(status: .disabled, note: nil)
    @Published private(set) var errorMessage: String?

    init(
        batteryService: BatteryService = BatteryService(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService()
    ) {
        self.batteryService = batteryService
        self.launchAtLoginService = launchAtLoginService

        batteryService.onPowerSourceChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(after: .milliseconds(400))
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }

        refresh()
        startRefreshTimer()
    }

    var displayText: String {
        guard batteryState.hasBattery else {
            return "--"
        }

        if batteryState.isFull {
            return "Full"
        }

        guard let minutes = batteryState.timeRemainingMinutes else {
            return "--"
        }

        return BatteryTimeFormatter.format(minutes: minutes)
    }

    var showsChargingBolt: Bool {
        batteryState.hasBattery && batteryState.isCharging && !batteryState.isFull
    }

    var headlineText: String {
        guard batteryState.hasBattery else {
            return "No battery detected"
        }

        if batteryState.isFull {
            return "Full"
        }

        guard let minutes = batteryState.timeRemainingMinutes else {
            return "Estimate unavailable"
        }

        let time = BatteryTimeFormatter.format(minutes: minutes)
        return batteryState.isCharging ? "\(time) to full" : "\(time) remaining"
    }

    var percentageText: String {
        guard let percentage = batteryState.percentage else {
            return "--"
        }

        return "\(percentage)%"
    }

    var statusText: String {
        guard batteryState.hasBattery else {
            return "No Battery"
        }

        if batteryState.isFull {
            return "Full"
        }

        if batteryState.isCharging {
            return "Charging"
        }

        switch batteryState.powerSource {
        case .battery:
            return "Discharging"
        case .ac:
            return "On AC Power"
        case .ups:
            return "On UPS"
        case .unknown:
            return "Unknown"
        }
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginState.toggleValue
    }

    var showsLaunchAtLoginSection: Bool {
        launchAtLoginState.isVisible
    }

    var showsLaunchAtLoginControl: Bool {
        launchAtLoginState.isControllable
    }

    var launchAtLoginStatusText: String {
        launchAtLoginState.statusText
    }

    var launchAtLoginMessage: String? {
        errorMessage ?? launchAtLoginState.note
    }

    func refresh() {
        batteryState = batteryService.fetchState()
        launchAtLoginState = launchAtLoginService.currentState()

        if errorMessage == launchAtLoginState.note {
            errorMessage = nil
        }
    }

    func scheduleRefresh(after delay: Duration = .zero) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }

            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard launchAtLoginState.isControllable else { return }

        errorMessage = nil

        do {
            launchAtLoginState = try launchAtLoginService.setEnabled(enabled)
            scheduleRefresh(after: .milliseconds(600))
        } catch {
            launchAtLoginState = launchAtLoginService.currentState()
            errorMessage = error.localizedDescription
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func startRefreshTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        timer.tolerance = 5
        refreshTimer = timer
    }
}
