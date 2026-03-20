import AppKit
import Combine
import Foundation

@MainActor
final class BatteryMenuViewModel: ObservableObject {
    private enum RefreshPolicy {
        static let fastInterval: TimeInterval = 1
        static let activeInterval: TimeInterval = 10
        static let idleInterval: TimeInterval = 30
        static let powerChangeFastWindow: TimeInterval = 15
    }

    private let batteryService: any BatteryStateService
    private let launchAtLoginService: LaunchAtLoginService
    private let chargingWattagePreferenceStore: any ChargingWattagePreferenceStore

    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var fastRefreshUntil: Date?
    private var hasLoadedInitialBatteryState = false

    @Published private(set) var batteryState = BatteryState(
        hasBattery: false,
        percentage: nil,
        isCharging: false,
        isFull: false,
        powerSource: .unknown,
        timeRemainingMinutes: nil,
        estimateDate: nil,
        estimateSource: .none
    )
    @Published private(set) var launchAtLoginState = LaunchAtLoginState(status: .disabled, note: nil)
    @Published private(set) var showsChargingWattageInMenuBar = false
    @Published private(set) var errorMessage: String?

    init(
        batteryService: any BatteryStateService = BatteryService(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(),
        chargingWattagePreferenceStore: any ChargingWattagePreferenceStore = UserDefaultsChargingWattagePreferenceStore(),
        autoRefresh: Bool = true
    ) {
        self.batteryService = batteryService
        self.launchAtLoginService = launchAtLoginService
        self.chargingWattagePreferenceStore = chargingWattagePreferenceStore
        self.showsChargingWattageInMenuBar = chargingWattagePreferenceStore.showsChargingWattageInMenuBar

        if autoRefresh {
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
                    self?.batteryService.invalidateTransientEstimateState(reason: "wake")
                    self?.activateFastRefreshWindow(duration: RefreshPolicy.fastInterval * 3)
                    self?.scheduleRefresh()
                }
            }

            refresh()
        } else {
            launchAtLoginState = launchAtLoginService.currentState()
        }
    }

    var displayText: String {
        let baseText: String

        guard batteryState.hasBattery else {
            return "--"
        }

        if batteryState.isFull {
            baseText = "Full"
            return menuBarDisplayText(baseText: baseText)
        }

        guard let minutes = batteryState.timeRemainingMinutes else {
            return "--"
        }

        baseText = BatteryTimeFormatter.format(minutes: minutes)
        return menuBarDisplayText(baseText: baseText)
    }

    var showsChargingBolt: Bool {
        batteryState.hasBattery && batteryState.isCharging && !batteryState.isFull
    }

    var showsMenuBarItem: Bool {
        BatteryMenuBarVisibilityPolicy.shouldShowItem(for: batteryState)
    }

    var headlineText: String {
        guard batteryState.hasBattery else {
            return "No battery detected"
        }

        if batteryState.isFull {
            return "Full"
        }

        if batteryState.powerSource == .ac && !batteryState.isCharging {
            return "Not charging"
        }

        guard let minutes = batteryState.timeRemainingMinutes else {
            return "Estimate unavailable"
        }

        let time = BatteryTimeFormatter.format(minutes: minutes)
        return batteryState.isCharging ? "\(time) to full" : "\(time) remaining"
    }

    var timeRemainingText: String {
        guard batteryState.hasBattery else {
            return "Unavailable"
        }

        if batteryState.isFull {
            return "Full"
        }

        if batteryState.powerSource == .ac && !batteryState.isCharging {
            return "Unavailable"
        }

        guard let minutes = batteryState.timeRemainingMinutes else {
            return "Estimate unavailable"
        }

        let time = BatteryTimeFormatter.format(minutes: minutes)
        return batteryState.isCharging ? "\(time) to full" : time
    }

    var stateIndicator: BatteryStateIndicator {
        BatteryStateIndicator.resolve(from: batteryState)
    }

    var stateIconName: String {
        stateIndicator.iconName
    }

    var stateDebugText: String {
        stateIndicator.label
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

        if batteryState.powerSource == .ac {
            return "Not Charging"
        }

        if batteryState.timeRemainingMinutes == nil, batteryState.powerSource == .battery || batteryState.powerSource == .ups {
            return "Estimate Pending"
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

    var dataSourceText: String {
        guard batteryState.hasBattery else {
            return "Unavailable"
        }

        if batteryState.isFull {
            return "Not Applicable"
        }

        return batteryState.estimateSource.menuLabel
    }

    var chargingPowerText: String? {
        guard let chargingWattageText else {
            return nil
        }

        return "Charging Power: \(chargingWattageText)"
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
        let previousBatteryState = batteryState
        let freshBatteryState = batteryService.fetchState()
        let stabilizedBatteryState = BatteryStateStabilizer.stabilize(previous: batteryState, fresh: freshBatteryState)
        batteryState = stabilizedBatteryState
        launchAtLoginState = launchAtLoginService.currentState()

        if hasLoadedInitialBatteryState, didMeaningfullyTransition(from: previousBatteryState, to: stabilizedBatteryState) {
            activateFastRefreshWindow(duration: RefreshPolicy.powerChangeFastWindow)
        }

        hasLoadedInitialBatteryState = true

        BatteryDebugLog.message(
            "ui-refresh raw[\(freshBatteryState.debugSummary)] ui[\(stabilizedBatteryState.debugSummary)]"
        )

        if errorMessage == launchAtLoginState.note {
            errorMessage = nil
        }

        scheduleNextRefreshTimer()
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

    func setShowsChargingWattageInMenuBar(_ enabled: Bool) {
        guard showsChargingWattageInMenuBar != enabled else { return }

        chargingWattagePreferenceStore.showsChargingWattageInMenuBar = enabled
        showsChargingWattageInMenuBar = enabled
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func activateFastRefreshWindow(duration: TimeInterval) {
        let candidate = Date().addingTimeInterval(duration)

        if let fastRefreshUntil {
            self.fastRefreshUntil = max(fastRefreshUntil, candidate)
        } else {
            fastRefreshUntil = candidate
        }

        scheduleNextRefreshTimer()
    }

    private func scheduleNextRefreshTimer() {
        refreshTimer?.invalidate()

        let interval = nextRefreshInterval()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }

        timer.tolerance = min(max(interval * 0.1, 0.2), 2)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func nextRefreshInterval() -> TimeInterval {
        if let fastRefreshUntil, fastRefreshUntil <= Date() {
            self.fastRefreshUntil = nil
        }

        if fastRefreshUntil != nil || shouldRefreshAggressively {
            return RefreshPolicy.fastInterval
        }

        if batteryState.hasBattery && !batteryState.isFull {
            return RefreshPolicy.activeInterval
        }

        return RefreshPolicy.idleInterval
    }

    private var shouldRefreshAggressively: Bool {
        batteryState.hasBattery && !batteryState.isFull && batteryState.timeRemainingMinutes == nil
    }

    private var chargingWattageText: String? {
        guard
            batteryState.hasBattery,
            batteryState.isCharging,
            !batteryState.isFull,
            let chargingWatts = batteryState.chargingWatts,
            chargingWatts > 0
        else {
            return nil
        }

        return "\(chargingWatts)W"
    }

    private func menuBarDisplayText(baseText: String) -> String {
        guard showsChargingWattageInMenuBar, let chargingWattageText else {
            return baseText
        }

        return "\(baseText) \(chargingWattageText)"
    }

    private func didMeaningfullyTransition(from previous: BatteryState, to current: BatteryState) -> Bool {
        previous.hasBattery != current.hasBattery
            || previous.powerSource != current.powerSource
            || previous.isCharging != current.isCharging
            || previous.isFull != current.isFull
    }
}
