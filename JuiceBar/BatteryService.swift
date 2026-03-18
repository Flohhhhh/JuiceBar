import Foundation
import IOKit.ps

final class BatteryService {
    var onPowerSourceChange: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?

    init() {
        installPowerSourceObserver()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.defaultMode)
        }
    }

    func fetchState() -> BatteryState {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sourceList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatteryState(
                hasBattery: false,
                percentage: nil,
                isCharging: false,
                isFull: false,
                powerSource: .unknown,
                timeRemainingMinutes: nil
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
            return BatteryState(
                hasBattery: false,
                percentage: nil,
                isCharging: false,
                isFull: false,
                powerSource: resolvedPowerSource(snapshot: snapshot),
                timeRemainingMinutes: nil
            )
        }

        let currentCapacity = batteryDescription[kIOPSCurrentCapacityKey] as? Int
        let maxCapacity = batteryDescription[kIOPSMaxCapacityKey] as? Int
        let percentage = percentage(currentCapacity: currentCapacity, maxCapacity: maxCapacity)
        let isCharging = (batteryDescription[kIOPSIsChargingKey] as? Bool) ?? false
        let isCharged = (batteryDescription[kIOPSIsChargedKey] as? Bool) ?? false
        let powerSource = resolvedPowerSource(snapshot: snapshot)

        return BatteryState(
            hasBattery: true,
            percentage: percentage,
            isCharging: isCharging,
            isFull: isCharged || percentage == 100,
            powerSource: powerSource,
            timeRemainingMinutes: resolvedTimeRemainingMinutes(
                powerSource: powerSource,
                isCharging: isCharging,
                description: batteryDescription
            )
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
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.defaultMode)
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

    private func resolvedTimeRemainingMinutes(
        powerSource: BatteryPowerSource,
        isCharging: Bool,
        description: [String: Any]
    ) -> Int? {
        if isCharging {
            return sanitizedMinutes(description[kIOPSTimeToFullChargeKey] as? Int)
        }

        if powerSource == .battery || powerSource == .ups {
            let estimate = IOPSGetTimeRemainingEstimate()
            if estimate > 0 {
                return max(1, Int(estimate / 60.0))
            }
        }

        return sanitizedMinutes(description[kIOPSTimeToEmptyKey] as? Int)
    }

    private func sanitizedMinutes(_ minutes: Int?) -> Int? {
        guard let minutes, minutes >= 0 else {
            return nil
        }

        return max(1, minutes)
    }
}
