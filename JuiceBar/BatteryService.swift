import Foundation
import IOKit
import IOKit.ps

struct BatteryRegistrySnapshot {
    var externalConnected: Bool?
    var externalChargeCapable: Bool?
    var isCharging: Bool?
    var rawCurrentCapacity: Int?
    var rawMaxCapacity: Int?
    var amperage: Int?
    var instantAmperage: Int?
    var timeRemainingMinutes: Int?
    var averageTimeToFullMinutes: Int?
    var averageTimeToEmptyMinutes: Int?

    var effectiveAmperage: Int? {
        if let amperage, amperage != 0 {
            return amperage
        }

        return instantAmperage
    }

    var isEffectivelyCharging: Bool? {
        if let effectiveAmperage {
            if effectiveAmperage < 0 {
                return false
            }

            if effectiveAmperage > 0 {
                return true
            }
        }

        if let isCharging {
            return isCharging
        }

        if let externalChargeCapable {
            return externalChargeCapable
        }

        return nil
    }
}

enum BatteryEstimateResolver {
    static func resolve(
        powerSource: BatteryPowerSource,
        isCharging: Bool,
        descriptionTimeToFullMinutes: Int?,
        descriptionTimeToEmptyMinutes: Int?,
        iopsEstimateSeconds: Double,
        registrySnapshot: BatteryRegistrySnapshot?
    ) -> Int? {
        if isCharging {
            return firstAvailable([
                sanitizedMinutes(descriptionTimeToFullMinutes),
                sanitizedMinutes(registrySnapshot?.averageTimeToFullMinutes)
            ])
        }

        let iopsMinutes = iopsEstimateSeconds > 0 ? max(1, Int(iopsEstimateSeconds / 60.0)) : nil
        let registryMinutes = firstAvailable([
            sanitizedMinutes(registrySnapshot?.timeRemainingMinutes),
            sanitizedMinutes(registrySnapshot?.averageTimeToEmptyMinutes)
        ])

        return firstAvailable([
            (powerSource == .battery || powerSource == .ups) ? iopsMinutes : nil,
            sanitizedMinutes(descriptionTimeToEmptyMinutes),
            registryMinutes
        ])
    }

    static func sanitizedMinutes(_ minutes: Int?) -> Int? {
        guard let minutes, minutes >= 0, minutes != 65_535 else {
            return nil
        }

        return max(1, minutes)
    }

    static func minutesFromAmperage(
        currentCapacity: Int?,
        maxCapacity: Int?,
        amperage: Int?,
        isCharging: Bool
    ) -> Int? {
        guard let amperage, amperage != 0 else {
            return nil
        }

        if isCharging {
            guard
                amperage > 0,
                let currentCapacity,
                let maxCapacity,
                maxCapacity > currentCapacity
            else {
                return nil
            }

            let remainingCapacity = maxCapacity - currentCapacity
            let hoursToFull = Double(remainingCapacity) / Double(amperage)
            return max(1, Int((hoursToFull * 60.0).rounded(.down)))
        }

        guard amperage < 0, let currentCapacity, currentCapacity > 0 else {
            return nil
        }

        let dischargeRate = Double(-amperage)
        let hoursToEmpty = Double(currentCapacity) / dischargeRate
        return max(1, Int((hoursToEmpty * 60.0).rounded(.down)))
    }

    private static func firstAvailable(_ values: [Int?]) -> Int? {
        values.compactMap { $0 }.first
    }
}

enum BatteryPowerSourceResolver {
    static func resolve(
        reportedPowerSource: BatteryPowerSource,
        registrySnapshot: BatteryRegistrySnapshot?,
        isCharging: Bool
    ) -> BatteryPowerSource {
        if reportedPowerSource == .ac {
            if registrySnapshot?.externalConnected == false {
                return .battery
            }

            if !isCharging, let effectiveAmperage = registrySnapshot?.effectiveAmperage, effectiveAmperage < 0 {
                return .battery
            }
        }

        return reportedPowerSource
    }
}

final class BatteryDischargeEstimateTracker {
    private struct Sample {
        let date: Date
        let currentCapacity: Int
        let dischargeRate: Int
    }

    private enum Policy {
        static let minimumSampleCount = 3
        static let minimumSampleSpan: TimeInterval = 2
        static let maximumSampleAge: TimeInterval = 30
        static let maximumSampleCount = 8
    }

    private var samples: [Sample] = []

    func reset() {
        samples.removeAll()
    }

    func recordAndEstimate(registrySnapshot: BatteryRegistrySnapshot?, now: Date = Date()) -> Int? {
        guard
            let currentCapacity = registrySnapshot?.rawCurrentCapacity,
            currentCapacity > 0,
            let effectiveAmperage = registrySnapshot?.effectiveAmperage,
            effectiveAmperage < 0
        else {
            pruneSamples(now: now)
            return nil
        }

        samples.append(
            Sample(
                date: now,
                currentCapacity: currentCapacity,
                dischargeRate: -effectiveAmperage
            )
        )
        pruneSamples(now: now)

        guard
            samples.count >= Policy.minimumSampleCount,
            let firstDate = samples.first?.date,
            now.timeIntervalSince(firstDate) >= Policy.minimumSampleSpan
        else {
            return nil
        }

        let medianRate = median(samples.map(\.dischargeRate))
        return max(1, Int((Double(currentCapacity) / Double(medianRate) * 60.0).rounded(.down)))
    }

    private func pruneSamples(now: Date) {
        samples.removeAll { now.timeIntervalSince($0.date) > Policy.maximumSampleAge }

        if samples.count > Policy.maximumSampleCount {
            samples.removeFirst(samples.count - Policy.maximumSampleCount)
        }
    }

    private func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let middleIndex = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middleIndex - 1] + sorted[middleIndex]) / 2
        }

        return sorted[middleIndex]
    }
}

private struct ResolvedBatteryEstimate {
    let minutes: Int?
    let source: BatteryEstimateSource
}

final class BatteryService {
    private enum PowerTransitionPolicy {
        static let dischargeWarmupWindow: TimeInterval = 2
        static let chargingWarmupWindow: TimeInterval = 8
    }

    var onPowerSourceChange: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private let dischargeEstimateTracker = BatteryDischargeEstimateTracker()
    private var lastObservedPowerSource: BatteryPowerSource?
    private var lastPowerSourceChangeDate: Date?
    private var lastObservedChargingState: Bool?
    private var lastChargingStateChangeDate: Date?

    init() {
        installPowerSourceObserver()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
        }
    }

    func fetchState() -> BatteryState {
        let now = Date()
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sourceList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            dischargeEstimateTracker.reset()
            return BatteryState(
                hasBattery: false,
                percentage: nil,
                isCharging: false,
                isFull: false,
                powerSource: .unknown,
                timeRemainingMinutes: nil,
                estimateDate: nil,
                estimateSource: .none
            )
        }

        let batteryDescription = sourceList
            .compactMap { IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any] }
            .first(where: { description in
                (description[kIOPSTransportTypeKey] as? String) == kIOPSInternalType
            }) ?? sourceList
            .compactMap { IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any] }
            .first

        guard let batteryDescription else {
            dischargeEstimateTracker.reset()
            return BatteryState(
                hasBattery: false,
                percentage: nil,
                isCharging: false,
                isFull: false,
                powerSource: resolvedPowerSource(snapshot: snapshot),
                timeRemainingMinutes: nil,
                estimateDate: nil,
                estimateSource: .none
            )
        }

        let currentCapacity = batteryDescription[kIOPSCurrentCapacityKey] as? Int
        let maxCapacity = batteryDescription[kIOPSMaxCapacityKey] as? Int
        let percentage = percentage(currentCapacity: currentCapacity, maxCapacity: maxCapacity)
        let registrySnapshot = currentRegistrySnapshot()
        let reportedPowerSource = resolvedPowerSource(snapshot: snapshot)
        let isCharging = resolvedIsCharging(
            description: batteryDescription,
            powerSource: reportedPowerSource,
            registrySnapshot: registrySnapshot
        )
        let powerSource = BatteryPowerSourceResolver.resolve(
            reportedPowerSource: reportedPowerSource,
            registrySnapshot: registrySnapshot,
            isCharging: isCharging
        )
        updatePowerSourceHistory(currentPowerSource: powerSource, now: now)
        updateChargingHistory(isCharging: isCharging, now: now)
        let isCharged = (batteryDescription[kIOPSIsChargedKey] as? Bool) ?? false
        let estimate = resolvedEstimate(
            powerSource: powerSource,
            isCharging: isCharging,
            description: batteryDescription,
            registrySnapshot: registrySnapshot,
            now: now
        )

        return BatteryState(
            hasBattery: true,
            percentage: percentage,
            isCharging: isCharging,
            isFull: isCharged || percentage == 100,
            powerSource: powerSource,
            timeRemainingMinutes: estimate.minutes,
            estimateDate: estimate.minutes == nil ? nil : now,
            estimateSource: estimate.source
        )
    }

    private func installPowerSourceObserver() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            service.onPowerSourceChange?()
        }, context)?.takeRetainedValue() else {
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
    }

    private func percentage(currentCapacity: Int?, maxCapacity: Int?) -> Int? {
        guard let currentCapacity, let maxCapacity, maxCapacity > 0 else {
            return currentCapacity
        }

        let rawValue = Double(currentCapacity) / Double(maxCapacity) * 100
        return Int(rawValue.rounded(.down))
    }

    private func resolvedPowerSource(snapshot: CFTypeRef) -> BatteryPowerSource {
        guard let powerSource = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
            return .unknown
        }

        switch powerSource {
        case kIOPMACPowerKey:
            return .ac
        case kIOPMBatteryPowerKey:
            return .battery
        case kIOPMUPSPowerKey:
            return .ups
        default:
            return .unknown
        }
    }

    private func resolvedEstimate(
        powerSource: BatteryPowerSource,
        isCharging: Bool,
        description: [String: Any],
        registrySnapshot: BatteryRegistrySnapshot?,
        now: Date
    ) -> ResolvedBatteryEstimate {
        if powerSource == .ac && !isCharging {
            dischargeEstimateTracker.reset()
            return ResolvedBatteryEstimate(minutes: nil, source: .none)
        }

        if isCharging {
            if let systemChargingEstimate = BatteryEstimateResolver.resolve(
                powerSource: powerSource,
                isCharging: true,
                descriptionTimeToFullMinutes: description[kIOPSTimeToFullChargeKey] as? Int,
                descriptionTimeToEmptyMinutes: description[kIOPSTimeToEmptyKey] as? Int,
                iopsEstimateSeconds: IOPSGetTimeRemainingEstimate(),
                registrySnapshot: registrySnapshot
            ), !isInChargingWarmupWindow(now: now) {
                return ResolvedBatteryEstimate(minutes: systemChargingEstimate, source: .system)
            }

            dischargeEstimateTracker.reset()
            return ResolvedBatteryEstimate(minutes: nil, source: .none)
        }

        let iopsEstimateSeconds = IOPSGetTimeRemainingEstimate()
        if (powerSource == .battery || powerSource == .ups), iopsEstimateSeconds > 0 {
            dischargeEstimateTracker.reset()
            return ResolvedBatteryEstimate(
                minutes: max(1, Int(iopsEstimateSeconds / 60.0)),
                source: .system
            )
        }

        if let descriptionEstimate = BatteryEstimateResolver.sanitizedMinutes(description[kIOPSTimeToEmptyKey] as? Int) {
            dischargeEstimateTracker.reset()
            return ResolvedBatteryEstimate(minutes: descriptionEstimate, source: .system)
        }

        let registryEstimate = BatteryEstimateResolver.sanitizedMinutes(registrySnapshot?.timeRemainingMinutes)
            ?? BatteryEstimateResolver.sanitizedMinutes(registrySnapshot?.averageTimeToEmptyMinutes)

        if let registryEstimate, !isInDischargeWarmupWindow(now: now, powerSource: powerSource) {
            return ResolvedBatteryEstimate(minutes: registryEstimate, source: .derived)
        }

        guard powerSource == .battery || powerSource == .ups, !isCharging else {
            dischargeEstimateTracker.reset()
            return ResolvedBatteryEstimate(minutes: nil, source: .none)
        }

        return ResolvedBatteryEstimate(
            minutes: dischargeEstimateTracker.recordAndEstimate(registrySnapshot: registrySnapshot, now: now),
            source: .derived
        )
    }

    private func updatePowerSourceHistory(currentPowerSource: BatteryPowerSource, now: Date) {
        if lastObservedPowerSource != currentPowerSource {
            lastObservedPowerSource = currentPowerSource
            lastPowerSourceChangeDate = now
        }
    }

    private func updateChargingHistory(isCharging: Bool, now: Date) {
        if lastObservedChargingState != isCharging {
            lastObservedChargingState = isCharging
            lastChargingStateChangeDate = now
        }
    }

    private func isInDischargeWarmupWindow(now: Date, powerSource: BatteryPowerSource) -> Bool {
        guard
            powerSource == .battery || powerSource == .ups,
            let lastPowerSourceChangeDate
        else {
            return false
        }

        return now.timeIntervalSince(lastPowerSourceChangeDate) < PowerTransitionPolicy.dischargeWarmupWindow
    }

    private func isInChargingWarmupWindow(now: Date) -> Bool {
        guard let lastChargingStateChangeDate else {
            return false
        }

        return lastObservedChargingState == true
            && now.timeIntervalSince(lastChargingStateChangeDate) < PowerTransitionPolicy.chargingWarmupWindow
    }

    private func resolvedIsCharging(
        description: [String: Any],
        powerSource: BatteryPowerSource,
        registrySnapshot: BatteryRegistrySnapshot?
    ) -> Bool {
        if powerSource == .battery || powerSource == .ups {
            return false
        }

        if let isCharging = description[kIOPSIsChargingKey] as? Bool {
            return isCharging
        }

        if let isCharging = registrySnapshot?.isCharging {
            return isCharging
        }

        return false
    }

    private func currentRegistrySnapshot() -> BatteryRegistrySnapshot? {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return nil
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOObjectRelease(service) }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let properties = propertiesRef?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }

        return BatteryRegistrySnapshot(
            externalConnected: boolValue(properties["ExternalConnected"]),
            externalChargeCapable: boolValue(properties["ExternalChargeCapable"]),
            isCharging: boolValue(properties["IsCharging"]),
            rawCurrentCapacity: numericValue(properties["AppleRawCurrentCapacity"]),
            rawMaxCapacity: numericValue(properties["AppleRawMaxCapacity"]),
            amperage: numericValue(properties["Amperage"]),
            instantAmperage: numericValue(properties["InstantAmperage"]),
            timeRemainingMinutes: numericValue(properties["TimeRemaining"]),
            averageTimeToFullMinutes: numericValue(properties["AvgTimeToFull"]),
            averageTimeToEmptyMinutes: numericValue(properties["AvgTimeToEmpty"])
        )
    }

    private func numericValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }

        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber {
            return number.boolValue
        }

        return value as? Bool
    }
}
