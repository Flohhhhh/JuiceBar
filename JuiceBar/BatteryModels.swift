import Foundation
import OSLog

enum BatteryPowerSource {
    case ac
    case battery
    case ups
    case unknown
}

enum BatteryEstimateSource: Equatable {
    case none
    case system
    case derived
}

enum BatteryEstimateKind {
    case charging
    case discharging
}

enum BatteryChargingPowerResolver {
    static let maximumChargingWatts = 200

    static func resolve(
        registrySnapshot: BatteryRegistrySnapshot?,
        isCharging: Bool,
        isFull: Bool
    ) -> Int? {
        guard
            isCharging,
            !isFull,
            let voltageMillivolts = registrySnapshot?.voltage,
            voltageMillivolts > 0,
            let amperageMilliamps = registrySnapshot?.effectiveAmperage,
            amperageMilliamps > 0
        else {
            return nil
        }

        let watts = Int(
            (Double(voltageMillivolts) * Double(amperageMilliamps) / 1_000_000.0)
                .rounded()
        )

        guard watts > 0, watts <= maximumChargingWatts else {
            return nil
        }

        return watts
    }
}

enum BatteryDebugLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.camerongustavson.JuiceBar",
        category: "Battery"
    )
    private static let enabled = ProcessInfo.processInfo.environment["JUICEBAR_BATTERY_DEBUG"] == "1"

    static func message(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let value = message()
        logger.debug("\(value, privacy: .public)")
    }
}

enum BatteryEstimateSafetyPolicy {
    static let maximumDischargeMinutes = 24 * 60
    static let maximumChargingMinutes = 12 * 60
    private static let sentinelMinutes = 65_535

    static func validatedMinutes(_ minutes: Int?, kind: BatteryEstimateKind, source: String) -> Int? {
        guard let minutes else {
            return nil
        }

        guard minutes > 0 else {
            BatteryDebugLog.message("estimate-safety drop source=\(source) reason=non-positive minutes=\(minutes)")
            return nil
        }

        guard minutes != sentinelMinutes else {
            BatteryDebugLog.message("estimate-safety drop source=\(source) reason=sentinel minutes=\(minutes)")
            return nil
        }

        let maximumMinutes = maximumMinutes(for: kind)
        guard minutes <= maximumMinutes else {
            BatteryDebugLog.message(
                "estimate-safety drop source=\(source) reason=exceeds-cap minutes=\(minutes) cap=\(maximumMinutes)"
            )
            return nil
        }

        return minutes
    }

    static func validatedDischargeMinutes(
        currentCapacity: Int?,
        dischargeRate: Int?,
        source: String
    ) -> Int? {
        guard
            let currentCapacity,
            currentCapacity > 0,
            let dischargeRate,
            dischargeRate > 0
        else {
            return nil
        }

        let minutes = max(1, Int((Double(currentCapacity) / Double(dischargeRate) * 60.0).rounded(.down)))
        return validatedMinutes(minutes, kind: .discharging, source: source)
    }

    static func kind(isCharging: Bool) -> BatteryEstimateKind {
        isCharging ? .charging : .discharging
    }

    private static func maximumMinutes(for kind: BatteryEstimateKind) -> Int {
        switch kind {
        case .charging:
            return maximumChargingMinutes
        case .discharging:
            return maximumDischargeMinutes
        }
    }
}

struct BatteryState: Equatable {
    var hasBattery: Bool
    var percentage: Int?
    var isCharging: Bool
    var isFull: Bool
    var powerSource: BatteryPowerSource
    var timeRemainingMinutes: Int?
    var estimateDate: Date?
    var estimateSource: BatteryEstimateSource = .none
    var chargingWatts: Int? = nil
}

extension BatteryPowerSource {
    var debugName: String {
        switch self {
        case .ac:
            return "ac"
        case .battery:
            return "battery"
        case .ups:
            return "ups"
        case .unknown:
            return "unknown"
        }
    }
}

extension BatteryEstimateSource {
    var debugName: String {
        switch self {
        case .none:
            return "none"
        case .system:
            return "system"
        case .derived:
            return "derived"
        }
    }

    var menuLabel: String {
        switch self {
        case .none:
            return "Unavailable"
        case .system:
            return "System Estimate"
        case .derived:
            return "Fallback Estimate"
        }
    }
}

enum BatteryStateIndicator: Equatable {
    case noBattery
    case full
    case charging
    case notCharging
    case dischargingSystem
    case dischargingDerived
    case pendingEstimate
    case acPower
    case upsPower
    case unknown

    var iconName: String {
        switch self {
        case .noBattery:
            return "questionmark.circle"
        case .full:
            return "checkmark.circle.fill"
        case .charging:
            return "bolt.fill"
        case .notCharging:
            return "pause.circle"
        case .dischargingSystem:
            return "battery.75"
        case .dischargingDerived:
            return "gauge"
        case .pendingEstimate:
            return "hourglass"
        case .acPower:
            return "powerplug"
        case .upsPower:
            return "powerplug.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .noBattery:
            return "No Battery"
        case .full:
            return "Full"
        case .charging:
            return "Charging"
        case .notCharging:
            return "Not Charging"
        case .dischargingSystem:
            return "System Estimate"
        case .dischargingDerived:
            return "Fallback Estimate"
        case .pendingEstimate:
            return "Waiting for Estimate"
        case .acPower:
            return "On AC Power"
        case .upsPower:
            return "On UPS"
        case .unknown:
            return "Unknown"
        }
    }

    static func resolve(from state: BatteryState) -> BatteryStateIndicator {
        guard state.hasBattery else {
            return .noBattery
        }

        if state.isFull {
            return .full
        }

        if state.isCharging {
            return .charging
        }

        if state.powerSource == .ac {
            return .notCharging
        }

        if state.powerSource == .battery || state.powerSource == .ups {
            if state.timeRemainingMinutes == nil {
                return .pendingEstimate
            }

            return state.estimateSource == .derived ? .dischargingDerived : .dischargingSystem
        }

        switch state.powerSource {
        case .ac:
            return .acPower
        case .ups:
            return .upsPower
        case .battery:
            return .pendingEstimate
        case .unknown:
            return .unknown
        }
    }
}

enum BatteryMenuBarVisibilityPolicy {
    static func shouldShowItem(for state: BatteryState) -> Bool {
        guard state.hasBattery else {
            return false
        }

        if state.isCharging {
            return state.timeRemainingMinutes != nil
        }

        if state.powerSource == .battery || state.powerSource == .ups {
            return state.timeRemainingMinutes != nil
        }

        return false
    }
}

enum BatteryStateStabilizer {
    private static let sameModeReuseWindow: TimeInterval = 90
    private static let derivedEstimateFreshWeight = 0.75

    static func stabilize(previous: BatteryState, fresh: BatteryState, now: Date = Date()) -> BatteryState {
        let sanitizedPrevious = sanitizedState(previous, source: "stabilizer-previous")
        let sanitizedFresh = sanitizedState(fresh, source: "stabilizer-fresh")
        let freshHadUnsafeEstimate = fresh.timeRemainingMinutes != nil && sanitizedFresh.timeRemainingMinutes == nil

        if freshHadUnsafeEstimate {
            return sanitizedFresh
        }

        if let smoothed = smoothedDerivedEstimate(previous: sanitizedPrevious, fresh: sanitizedFresh) {
            return smoothed
        }

        guard
            sanitizedFresh.timeRemainingMinutes == nil,
            let previousMinutes = sanitizedPrevious.timeRemainingMinutes,
            let estimateDate = sanitizedPrevious.estimateDate,
            sanitizedPrevious.hasBattery,
            sanitizedFresh.hasBattery,
            !sanitizedFresh.isFull
        else {
            return sanitizedFresh
        }

        let estimateAge = now.timeIntervalSince(estimateDate)
        guard estimateAge >= 0 else {
            return sanitizedFresh
        }

        if sanitizedPrevious.isCharging == sanitizedFresh.isCharging,
            sanitizedPrevious.isFull == sanitizedFresh.isFull,
            estimateAge <= sameModeReuseWindow
        {
            guard sanitizedPrevious.powerSource == sanitizedFresh.powerSource else {
                return sanitizedFresh
            }

            return sanitizedFresh.withEstimate(previousMinutes, date: estimateDate)
        }

        return sanitizedFresh
    }

    private static func smoothedDerivedEstimate(previous: BatteryState, fresh: BatteryState) -> BatteryState? {
        guard
            fresh.estimateSource == .derived,
            let freshMinutes = fresh.timeRemainingMinutes,
            let previousMinutes = previous.timeRemainingMinutes,
            previous.hasBattery,
            fresh.hasBattery,
            previous.isCharging == fresh.isCharging,
            previous.isFull == fresh.isFull,
            previous.powerSource == fresh.powerSource
        else {
            return nil
        }

        let kind = BatteryEstimateSafetyPolicy.kind(isCharging: fresh.isCharging)
        guard
            BatteryEstimateSafetyPolicy.validatedMinutes(
                previousMinutes,
                kind: kind,
                source: "stabilizer-derived-previous"
            ) != nil,
            BatteryEstimateSafetyPolicy.validatedMinutes(
                freshMinutes,
                kind: kind,
                source: "stabilizer-derived-fresh"
            ) != nil
        else {
            return nil
        }

        let smoothedMinutes = Int(
            (Double(previousMinutes) * (1 - derivedEstimateFreshWeight) + Double(freshMinutes) * derivedEstimateFreshWeight)
                .rounded()
        )

        guard let validatedSmoothedMinutes = BatteryEstimateSafetyPolicy.validatedMinutes(
            smoothedMinutes,
            kind: kind,
            source: "stabilizer-derived-smoothed"
        ) else {
            return fresh.withoutEstimate()
        }

        return fresh.withEstimate(validatedSmoothedMinutes, date: fresh.estimateDate ?? Date(), source: .derived)
    }

    private static func sanitizedState(_ state: BatteryState, source: String) -> BatteryState {
        guard let minutes = state.timeRemainingMinutes else {
            return state
        }

        let kind = BatteryEstimateSafetyPolicy.kind(isCharging: state.isCharging)
        guard BatteryEstimateSafetyPolicy.validatedMinutes(minutes, kind: kind, source: source) != nil else {
            return state.withoutEstimate()
        }

        return state
    }
}

extension BatteryState {
    func withEstimate(_ minutes: Int, date: Date, source: BatteryEstimateSource? = nil) -> BatteryState {
        var copy = self
        copy.timeRemainingMinutes = minutes
        copy.estimateDate = date
        if let source {
            copy.estimateSource = source
        }
        return copy
    }

    func withoutEstimate() -> BatteryState {
        var copy = self
        copy.timeRemainingMinutes = nil
        copy.estimateDate = nil
        copy.estimateSource = .none
        return copy
    }

    var debugSummary: String {
        [
            "battery=\(hasBattery)",
            "pct=\(percentage.map(String.init) ?? "nil")",
            "source=\(powerSource.debugName)",
            "charging=\(isCharging)",
            "full=\(isFull)",
            "minutes=\(timeRemainingMinutes.map(String.init) ?? "nil")",
            "estimateSource=\(estimateSource.debugName)",
            "watts=\(chargingWatts.map(String.init) ?? "nil")"
        ].joined(separator: " ")
    }
}
