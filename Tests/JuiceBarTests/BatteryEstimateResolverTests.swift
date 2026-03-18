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
}
