import Foundation

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

struct BatteryState: Equatable {
    var hasBattery: Bool
    var percentage: Int?
    var isCharging: Bool
    var isFull: Bool
    var powerSource: BatteryPowerSource
    var timeRemainingMinutes: Int?
    var estimateDate: Date?
    var estimateSource: BatteryEstimateSource = .none
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

enum BatteryStateStabilizer {
    private static let sameModeReuseWindow: TimeInterval = 90
    private static let derivedEstimateFreshWeight = 0.75

    static func stabilize(previous: BatteryState, fresh: BatteryState, now: Date = Date()) -> BatteryState {
        if let smoothed = smoothedDerivedEstimate(previous: previous, fresh: fresh) {
            return smoothed
        }

        guard
            fresh.timeRemainingMinutes == nil,
            let previousMinutes = previous.timeRemainingMinutes,
            let estimateDate = previous.estimateDate,
            previous.hasBattery,
            fresh.hasBattery,
            !fresh.isFull
        else {
            return fresh
        }

        let estimateAge = now.timeIntervalSince(estimateDate)
        guard estimateAge >= 0 else {
            return fresh
        }

        if previous.isCharging == fresh.isCharging, previous.isFull == fresh.isFull, estimateAge <= sameModeReuseWindow {
            guard previous.powerSource == fresh.powerSource else {
                return fresh
            }

            return fresh.withEstimate(previousMinutes, date: estimateDate)
        }

        return fresh
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

        let smoothedMinutes = Int(
            (Double(previousMinutes) * (1 - derivedEstimateFreshWeight) + Double(freshMinutes) * derivedEstimateFreshWeight)
                .rounded()
        )

        return fresh.withEstimate(smoothedMinutes, date: fresh.estimateDate ?? Date(), source: .derived)
    }
}

private extension BatteryState {
    func withEstimate(_ minutes: Int, date: Date, source: BatteryEstimateSource? = nil) -> BatteryState {
        var copy = self
        copy.timeRemainingMinutes = minutes
        copy.estimateDate = date
        if let source {
            copy.estimateSource = source
        }
        return copy
    }
}
