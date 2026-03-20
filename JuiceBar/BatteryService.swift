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
    var voltage: Int? = nil
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
                sanitizedMinutes(descriptionTimeToFullMinutes, kind: .charging, source: "resolver-description-full"),
                sanitizedMinutes(
                    registrySnapshot?.averageTimeToFullMinutes,
                    kind: .charging,
                    source: "resolver-registry-full"
                )
            ])
        }

        let iopsMinutes = iopsEstimateSeconds > 0
            ? sanitizedMinutes(
                max(1, Int(iopsEstimateSeconds / 60.0)),
                kind: .discharging,
                source: "resolver-iops-empty"
            )
            : nil
        let registryMinutes = firstAvailable([
            sanitizedMinutes(
                registrySnapshot?.timeRemainingMinutes,
                kind: .discharging,
                source: "resolver-registry-empty"
            ),
            sanitizedMinutes(
                registrySnapshot?.averageTimeToEmptyMinutes,
                kind: .discharging,
                source: "resolver-registry-avg-empty"
            )
        ])

        return firstAvailable([
            (powerSource == .battery || powerSource == .ups) ? iopsMinutes : nil,
            sanitizedMinutes(
                descriptionTimeToEmptyMinutes,
                kind: .discharging,
                source: "resolver-description-empty"
            ),
            registryMinutes
        ])
    }

    static func sanitizedMinutes(
        _ minutes: Int?,
        kind: BatteryEstimateKind = .discharging,
        source: String = "resolver"
    ) -> Int? {
        BatteryEstimateSafetyPolicy.validatedMinutes(minutes, kind: kind, source: source)
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
            let minutes = max(1, Int((hoursToFull * 60.0).rounded(.down)))
            return BatteryEstimateSafetyPolicy.validatedMinutes(
                minutes,
                kind: .charging,
                source: "resolver-amperage-full"
            )
        }

        guard amperage < 0, let currentCapacity, currentCapacity > 0 else {
            return nil
        }

        return BatteryEstimateSafetyPolicy.validatedDischargeMinutes(
            currentCapacity: currentCapacity,
            dischargeRate: -amperage,
            source: "resolver-amperage-empty"
        )
    }

    static func shouldPreferDescriptionEstimate(
        descriptionEstimate: Int?,
        registryEstimate: Int?,
        reportedPowerSource: BatteryPowerSource,
        effectivePowerSource: BatteryPowerSource,
        registrySnapshot: BatteryRegistrySnapshot?
    ) -> Bool {
        guard let descriptionEstimate else {
            return false
        }

        if reportedPowerSource != effectivePowerSource {
            return false
        }

        if effectivePowerSource == .battery || effectivePowerSource == .ups {
            if registrySnapshot?.externalConnected == true {
                return false
            }

            if let effectiveAmperage = registrySnapshot?.effectiveAmperage, effectiveAmperage > 0 {
                return false
            }
        }

        if descriptionEstimate <= 1, registryEstimate != nil {
            return false
        }

        return true
    }

    private static func firstAvailable(_ values: [Int?]) -> Int? {
        values.compactMap { $0 }.first
    }
}

enum BatteryPowerSourceResolver {
    static func resolve(
        reportedPowerSource: BatteryPowerSource,
        registrySnapshot: BatteryRegistrySnapshot?,
        isCharging: Bool,
        previousPowerSource: BatteryPowerSource?
    ) -> BatteryPowerSource {
        if reportedPowerSource == .ac {
            if registrySnapshot?.externalConnected == false {
                return .battery
            }

            if previousPowerSource == .battery || previousPowerSource == .ups {
                return .ac
            }

            if !isCharging, let effectiveAmperage = registrySnapshot?.effectiveAmperage, effectiveAmperage < 0 {
                return .battery
            }
        }

        return reportedPowerSource
    }
}

struct PersistedDischargeRateBaseline {
    var shortTermRate: Int?
    var longTermRate: Int?
}

private struct PersistedDischargeRates: Codable {
    var shortTermRate: Int?
    var shortTermUpdatedAt: Date?
    var longTermRate: Int?
    var longTermUpdatedAt: Date?
}

protocol BatteryDischargeRateStore {
    func loadBaseline(now: Date) -> PersistedDischargeRateBaseline
    func recordObservedRate(_ dischargeRate: Int, now: Date)
}

final class UserDefaultsBatteryDischargeRateStore: BatteryDischargeRateStore {
    private enum Policy {
        static let shortTermMaxAge: TimeInterval = 7 * 24 * 60 * 60
        static let longTermMaxAge: TimeInterval = 30 * 24 * 60 * 60
        static let shortTermFreshWeight = 0.35
        static let longTermFreshWeight = 0.1
    }

    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "BatteryDischargeRateBaselines"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadBaseline(now: Date) -> PersistedDischargeRateBaseline {
        guard let persisted = persistedRates() else {
            return PersistedDischargeRateBaseline(shortTermRate: nil, longTermRate: nil)
        }

        return PersistedDischargeRateBaseline(
            shortTermRate: isFresh(persisted.shortTermUpdatedAt, now: now, maxAge: Policy.shortTermMaxAge)
                ? persisted.shortTermRate
                : nil,
            longTermRate: isFresh(persisted.longTermUpdatedAt, now: now, maxAge: Policy.longTermMaxAge)
                ? persisted.longTermRate
                : nil
        )
    }

    func recordObservedRate(_ dischargeRate: Int, now: Date) {
        guard dischargeRate > 0 else {
            return
        }

        var persisted = persistedRates() ?? PersistedDischargeRates()
        persisted.shortTermRate = blendedRate(
            existingRate: persisted.shortTermRate,
            freshRate: dischargeRate,
            freshWeight: Policy.shortTermFreshWeight
        )
        persisted.shortTermUpdatedAt = now
        persisted.longTermRate = blendedRate(
            existingRate: persisted.longTermRate,
            freshRate: dischargeRate,
            freshWeight: Policy.longTermFreshWeight
        )
        persisted.longTermUpdatedAt = now
        save(persisted)
    }

    private func blendedRate(existingRate: Int?, freshRate: Int, freshWeight: Double) -> Int {
        guard let existingRate else {
            return freshRate
        }

        return Int(
            (Double(existingRate) * (1 - freshWeight) + Double(freshRate) * freshWeight)
                .rounded()
        )
    }

    private func persistedRates() -> PersistedDischargeRates? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(PersistedDischargeRates.self, from: data)
    }

    private func save(_ persisted: PersistedDischargeRates) {
        guard let data = try? encoder.encode(persisted) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    private func isFresh(_ updatedAt: Date?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let updatedAt else {
            return false
        }

        let age = now.timeIntervalSince(updatedAt)
        return age >= 0 && age <= maxAge
    }
}

final class BatteryDischargeEstimateTracker {
    private struct Sample {
        let date: Date
        let currentCapacity: Int
        let dischargeRate: Int
    }

    private struct CachedRate {
        let dischargeRate: Int
    }

    private enum Policy {
        static let minimumSampleCount = 3
        static let minimumSampleSpan: TimeInterval = 2
        static let maximumSampleAge: TimeInterval = 30
        static let maximumSampleCount = 8
    }

    private let rateStore: any BatteryDischargeRateStore
    private var samples: [Sample] = []
    private var cachedRate: CachedRate?

    init(rateStore: any BatteryDischargeRateStore = UserDefaultsBatteryDischargeRateStore()) {
        self.rateStore = rateStore
    }

    func reset() {
        samples.removeAll()
    }

    func invalidateTransientState() {
        reset()
        cachedRate = nil
    }

    func debugSummary(now: Date = Date()) -> String {
        let persistedBaseline = rateStore.loadBaseline(now: now)
        let cachedSummary: String
        if let cachedRate {
            cachedSummary = " cachedRate=\(cachedRate.dischargeRate)"
        } else {
            cachedSummary = " cachedRate=nil"
        }
        let persistedSummary = " shortRate=\(persistedBaseline.shortTermRate.map(String.init) ?? "nil")"
            + " longRate=\(persistedBaseline.longTermRate.map(String.init) ?? "nil")"

        guard let first = samples.first, let last = samples.last else {
            return "samples=0\(cachedSummary)\(persistedSummary)"
        }

        let span = String(format: "%.1fs", last.date.timeIntervalSince(first.date))
        let medianRate = median(samples.map(\.dischargeRate))
        return "samples=\(samples.count) span=\(span) medianRate=\(medianRate)\(cachedSummary)\(persistedSummary)"
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
        guard let minutes = BatteryEstimateSafetyPolicy.validatedDischargeMinutes(
            currentCapacity: currentCapacity,
            dischargeRate: medianRate,
            source: "tracker-observed-rate"
        ) else {
            return nil
        }

        cachedRate = CachedRate(dischargeRate: medianRate)
        rateStore.recordObservedRate(medianRate, now: now)
        return minutes
    }

    func estimateUsingCachedRate(registrySnapshot: BatteryRegistrySnapshot?, now: Date = Date()) -> Int? {
        guard
            let currentCapacity = registrySnapshot?.rawCurrentCapacity,
            currentCapacity > 0
        else {
            return nil
        }

        let persistedBaseline = rateStore.loadBaseline(now: now)
        let candidates: [(Int?, String)] = [
            (cachedRate?.dischargeRate, "tracker-session-cache"),
            (persistedBaseline.shortTermRate, "tracker-persisted-short"),
            (persistedBaseline.longTermRate, "tracker-persisted-long")
        ]

        for (dischargeRate, source) in candidates {
            if let minutes = BatteryEstimateSafetyPolicy.validatedDischargeMinutes(
                currentCapacity: currentCapacity,
                dischargeRate: dischargeRate,
                source: source
            ) {
                return minutes
            }
        }

        return nil
    }

    func cacheResolvedEstimate(registrySnapshot: BatteryRegistrySnapshot?, minutes: Int?) {
        guard
            let currentCapacity = registrySnapshot?.rawCurrentCapacity,
            currentCapacity > 0,
            let safeMinutes = BatteryEstimateSafetyPolicy.validatedMinutes(
                minutes,
                kind: .discharging,
                source: "tracker-resolved-seed"
            ),
            let effectiveAmperage = registrySnapshot?.effectiveAmperage,
            effectiveAmperage < 0
        else {
            return
        }

        let dischargeRate = max(1, Int((Double(currentCapacity) / Double(safeMinutes) * 60.0).rounded()))
        guard BatteryEstimateSafetyPolicy.validatedDischargeMinutes(
            currentCapacity: currentCapacity,
            dischargeRate: dischargeRate,
            source: "tracker-resolved-seed-rate"
        ) != nil else {
            return
        }

        let observedRate = -effectiveAmperage
        let largerRate = max(dischargeRate, observedRate)
        let smallerRate = max(1, min(dischargeRate, observedRate))

        guard Double(largerRate) / Double(smallerRate) <= 25 else {
            return
        }

        cachedRate = CachedRate(dischargeRate: dischargeRate)
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

protocol BatteryStateService: AnyObject {
    var onPowerSourceChange: (() -> Void)? { get set }

    func invalidateTransientEstimateState(reason: String)
    func fetchState() -> BatteryState
}

final class BatteryService: BatteryStateService {
    private enum PowerTransitionPolicy {
        static let dischargeWarmupWindow: TimeInterval = 2
        static let provisionalDischargeDelay: TimeInterval = 1
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

    func invalidateTransientEstimateState(reason: String = "manual") {
        BatteryDebugLog.message("event=estimate-transient-invalidation reason=\(reason)")
        dischargeEstimateTracker.invalidateTransientState()
    }

    func fetchState() -> BatteryState {
        let now = Date()
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sourceList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            invalidateTransientEstimateState(reason: "no-power-sources")
            BatteryDebugLog.message("refresh raw=no-power-sources")
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
            invalidateTransientEstimateState(reason: "no-internal-battery")
            BatteryDebugLog.message("refresh raw=no-internal-battery reportedSource=\(resolvedPowerSource(snapshot: snapshot).debugName)")
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
            isCharging: isCharging,
            previousPowerSource: lastObservedPowerSource
        )
        updatePowerSourceHistory(currentPowerSource: powerSource, now: now)
        updateChargingHistory(isCharging: isCharging, now: now)
        let isCharged = (batteryDescription[kIOPSIsChargedKey] as? Bool) ?? false
        let estimate = resolvedEstimate(
            reportedPowerSource: reportedPowerSource,
            powerSource: powerSource,
            isCharging: isCharging,
            description: batteryDescription,
            registrySnapshot: registrySnapshot,
            now: now
        )
        let isFull = isCharged || percentage == 100
        let chargingWatts = BatteryChargingPowerResolver.resolve(
            registrySnapshot: registrySnapshot,
            isCharging: isCharging,
            isFull: isFull
        )
        let state = BatteryState(
            hasBattery: true,
            percentage: percentage,
            isCharging: isCharging,
            isFull: isFull,
            powerSource: powerSource,
            timeRemainingMinutes: estimate.minutes,
            estimateDate: estimate.minutes == nil ? nil : now,
            estimateSource: estimate.source,
            chargingWatts: chargingWatts
        )

        logRefresh(
            reportedPowerSource: reportedPowerSource,
            effectivePowerSource: powerSource,
            description: batteryDescription,
            registrySnapshot: registrySnapshot,
            estimate: estimate,
            state: state,
            now: now
        )

        return state
    }

    private func installPowerSourceObserver() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            BatteryDebugLog.message("event=power-source-notification")
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
        reportedPowerSource: BatteryPowerSource,
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

        let trackerEstimate = dischargeEstimateTracker.recordAndEstimate(registrySnapshot: registrySnapshot, now: now)
        let iopsEstimateSeconds = IOPSGetTimeRemainingEstimate()
        let iopsMinutes = iopsEstimateSeconds > 0
            ? BatteryEstimateResolver.sanitizedMinutes(
                max(1, Int(iopsEstimateSeconds / 60.0)),
                kind: .discharging,
                source: "service-iops-empty"
            )
            : nil
        if (powerSource == .battery || powerSource == .ups), let iopsMinutes {
            dischargeEstimateTracker.cacheResolvedEstimate(
                registrySnapshot: registrySnapshot,
                minutes: iopsMinutes
            )
            dischargeEstimateTracker.reset()
            return ResolvedBatteryEstimate(
                minutes: iopsMinutes,
                source: .system
            )
        }

        let descriptionEstimate = BatteryEstimateResolver.sanitizedMinutes(
            description[kIOPSTimeToEmptyKey] as? Int,
            kind: .discharging,
            source: "service-description-empty"
        )
        let registryEstimate = BatteryEstimateResolver.sanitizedMinutes(
            registrySnapshot?.timeRemainingMinutes,
            kind: .discharging,
            source: "service-registry-empty"
        ) ?? BatteryEstimateResolver.sanitizedMinutes(
            registrySnapshot?.averageTimeToEmptyMinutes,
            kind: .discharging,
            source: "service-registry-avg-empty"
        )

        if BatteryEstimateResolver.shouldPreferDescriptionEstimate(
            descriptionEstimate: descriptionEstimate,
            registryEstimate: registryEstimate,
            reportedPowerSource: reportedPowerSource,
            effectivePowerSource: powerSource,
            registrySnapshot: registrySnapshot
        ), let descriptionEstimate {
            dischargeEstimateTracker.cacheResolvedEstimate(
                registrySnapshot: registrySnapshot,
                minutes: descriptionEstimate
            )
            dischargeEstimateTracker.reset()
            return ResolvedBatteryEstimate(minutes: descriptionEstimate, source: .system)
        }

        if let registryEstimate, !isInDischargeWarmupWindow(now: now, powerSource: powerSource) {
            dischargeEstimateTracker.cacheResolvedEstimate(
                registrySnapshot: registrySnapshot,
                minutes: registryEstimate
            )
            return ResolvedBatteryEstimate(minutes: registryEstimate, source: .derived)
        }

        guard powerSource == .battery || powerSource == .ups, !isCharging else {
            dischargeEstimateTracker.reset()
            return ResolvedBatteryEstimate(minutes: nil, source: .none)
        }

        if let trackerEstimate {
            return ResolvedBatteryEstimate(minutes: trackerEstimate, source: .derived)
        }

        if shouldUseProvisionalDischargeEstimate(now: now, powerSource: powerSource) {
            return ResolvedBatteryEstimate(
                minutes: dischargeEstimateTracker.estimateUsingCachedRate(
                    registrySnapshot: registrySnapshot,
                    now: now
                ),
                source: .derived
            )
        }

        return ResolvedBatteryEstimate(
            minutes: nil,
            source: .derived
        )
    }

    private func updatePowerSourceHistory(currentPowerSource: BatteryPowerSource, now: Date) {
        if lastObservedPowerSource != currentPowerSource {
            let previousPowerSource = lastObservedPowerSource?.debugName ?? "nil"
            lastObservedPowerSource = currentPowerSource
            lastPowerSourceChangeDate = now
            invalidateTransientEstimateState(reason: "power-source-transition")
            BatteryDebugLog.message(
                "event=power-source-transition previous=\(previousPowerSource) current=\(currentPowerSource.debugName)"
            )
        }
    }

    private func updateChargingHistory(isCharging: Bool, now: Date) {
        if lastObservedChargingState != isCharging {
            let previousChargingState = lastObservedChargingState.map(String.init) ?? "nil"
            lastObservedChargingState = isCharging
            lastChargingStateChangeDate = now
            if isCharging {
                invalidateTransientEstimateState(reason: "charging-started")
            }
            BatteryDebugLog.message(
                "event=charging-transition previous=\(previousChargingState) current=\(isCharging)"
            )
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

    private func shouldUseProvisionalDischargeEstimate(now: Date, powerSource: BatteryPowerSource) -> Bool {
        guard powerSource == .battery || powerSource == .ups else {
            return false
        }

        guard let lastPowerSourceChangeDate else {
            return true
        }

        return now.timeIntervalSince(lastPowerSourceChangeDate) >= PowerTransitionPolicy.provisionalDischargeDelay
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
            voltage: numericValue(properties["Voltage"]),
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

    private func logRefresh(
        reportedPowerSource: BatteryPowerSource,
        effectivePowerSource: BatteryPowerSource,
        description: [String: Any],
        registrySnapshot: BatteryRegistrySnapshot?,
        estimate: ResolvedBatteryEstimate,
        state: BatteryState,
        now: Date
    ) {
        let iopsEstimateSeconds = IOPSGetTimeRemainingEstimate()
        let iopsMinutes = iopsEstimateSeconds > 0
            ? BatteryEstimateResolver.sanitizedMinutes(
                max(1, Int(iopsEstimateSeconds / 60.0)),
                kind: .discharging,
                source: "log-iops-empty"
            ).map(String.init) ?? "nil"
            : "nil"
        let descriptionTimeToEmpty = BatteryEstimateResolver.sanitizedMinutes(
            description[kIOPSTimeToEmptyKey] as? Int,
            kind: .discharging,
            source: "log-description-empty"
        ).map(String.init) ?? "nil"
        let descriptionTimeToFull = BatteryEstimateResolver.sanitizedMinutes(
            description[kIOPSTimeToFullChargeKey] as? Int,
            kind: .charging,
            source: "log-description-full"
        ).map(String.init) ?? "nil"
        let dischargeWarmup = isInDischargeWarmupWindow(now: now, powerSource: effectivePowerSource)
        let chargingWarmup = isInChargingWarmupWindow(now: now)

        BatteryDebugLog.message(
            """
            refresh \
            reported=\(reportedPowerSource.debugName) \
            effective=\(effectivePowerSource.debugName) \
            descEmpty=\(descriptionTimeToEmpty) \
            descFull=\(descriptionTimeToFull) \
            iops=\(iopsMinutes) \
            regExternal=\(stringValue(registrySnapshot?.externalConnected)) \
            regAmp=\(stringValue(registrySnapshot?.amperage)) \
            regVolt=\(stringValue(registrySnapshot?.voltage)) \
            regTimeRemaining=\(stringValue(registrySnapshot?.timeRemainingMinutes)) \
            regAvgEmpty=\(stringValue(registrySnapshot?.averageTimeToEmptyMinutes)) \
            dischargeWarmup=\(dischargeWarmup) \
            chargingWarmup=\(chargingWarmup) \
            tracker=\(dischargeEstimateTracker.debugSummary(now: now)) \
            resultMinutes=\(stringValue(estimate.minutes)) \
            resultSource=\(estimate.source.debugName) \
            state[\(state.debugSummary)]
            """
        )
    }

    private func stringValue<T>(_ value: T?) -> String {
        value.map { String(describing: $0) } ?? "nil"
    }
}
