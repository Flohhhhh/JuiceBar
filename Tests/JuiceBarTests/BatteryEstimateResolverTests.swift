import Foundation
import Testing
@testable import JuiceBar

struct BatteryEstimateResolverTests {
    @Test func chargingWithoutAppleEstimateReturnsNil() {
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 4100,
            rawMaxCapacity: 5481,
            amperage: 1381,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        let minutes = BatteryEstimateResolver.resolve(
            powerSource: .ac,
            isCharging: true,
            descriptionTimeToFullMinutes: nil,
            descriptionTimeToEmptyMinutes: nil,
            iopsEstimateSeconds: -1,
            registrySnapshot: snapshot
        )

        #expect(minutes == nil)
    }

    @Test func registrySentinelMinutesAreIgnored() {
        #expect(BatteryEstimateResolver.sanitizedMinutes(65_535) == nil)
    }

    @Test func dischargeEstimatesAboveSafetyCapAreIgnored() {
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5126,
            rawMaxCapacity: 5481,
            amperage: -819,
            instantAmperage: nil,
            timeRemainingMinutes: 2_000,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: 1_800
        )

        let minutes = BatteryEstimateResolver.resolve(
            powerSource: .battery,
            isCharging: false,
            descriptionTimeToFullMinutes: nil,
            descriptionTimeToEmptyMinutes: 1_700,
            iopsEstimateSeconds: 1_600 * 60,
            registrySnapshot: snapshot
        )

        #expect(minutes == nil)
    }

    @Test func chargingEstimatesAboveSafetyCapAreIgnored() {
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 4100,
            rawMaxCapacity: 5481,
            amperage: 1381,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: 900,
            averageTimeToEmptyMinutes: nil
        )

        let minutes = BatteryEstimateResolver.resolve(
            powerSource: .ac,
            isCharging: true,
            descriptionTimeToFullMinutes: 840,
            descriptionTimeToEmptyMinutes: nil,
            iopsEstimateSeconds: -1,
            registrySnapshot: snapshot
        )

        #expect(minutes == nil)
    }

    @Test func registryTimeRemainingBeatsDerivedFallbacks() {
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5126,
            rawMaxCapacity: 5481,
            amperage: -819,
            instantAmperage: nil,
            timeRemainingMinutes: 399,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: 401
        )

        let minutes = BatteryEstimateResolver.resolve(
            powerSource: .battery,
            isCharging: false,
            descriptionTimeToFullMinutes: nil,
            descriptionTimeToEmptyMinutes: nil,
            iopsEstimateSeconds: -1,
            registrySnapshot: snapshot
        )

        #expect(minutes == 399)
    }

    @Test func dischargingWithoutAppleEstimateReturnsNil() {
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5126,
            rawMaxCapacity: 5481,
            amperage: -819,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        let minutes = BatteryEstimateResolver.resolve(
            powerSource: .battery,
            isCharging: false,
            descriptionTimeToFullMinutes: nil,
            descriptionTimeToEmptyMinutes: nil,
            iopsEstimateSeconds: -1,
            registrySnapshot: snapshot
        )

        #expect(minutes == nil)
    }

    @Test func transitionDescriptionEstimateIsIgnoredWhenRegistryLooksBetter() {
        let snapshot = BatteryRegistrySnapshot(
            externalConnected: true,
            rawCurrentCapacity: 5000,
            rawMaxCapacity: 5800,
            amperage: -728,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: 327
        )

        let shouldPreferDescriptionEstimate = BatteryEstimateResolver.shouldPreferDescriptionEstimate(
            descriptionEstimate: 1,
            registryEstimate: 327,
            reportedPowerSource: .ac,
            effectivePowerSource: .battery,
            registrySnapshot: snapshot
        )

        #expect(shouldPreferDescriptionEstimate == false)
    }
}
