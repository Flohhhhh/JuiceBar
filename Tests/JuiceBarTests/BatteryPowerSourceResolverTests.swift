import Testing
@testable import JuiceBar

struct BatteryPowerSourceResolverTests {
    @Test func unpluggedBatteryOverridesLaggingAcReport() {
        let snapshot = BatteryRegistrySnapshot(
            externalConnected: false,
            externalChargeCapable: false,
            isCharging: false,
            rawCurrentCapacity: 5000,
            rawMaxCapacity: 5800,
            amperage: -1200,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        let powerSource = BatteryPowerSourceResolver.resolve(
            reportedPowerSource: .ac,
            registrySnapshot: snapshot,
            isCharging: false,
            previousPowerSource: .ac
        )

        #expect(powerSource == .battery)
    }

    @Test func pluggedInNotChargingRemainsAcPower() {
        let snapshot = BatteryRegistrySnapshot(
            externalConnected: true,
            externalChargeCapable: true,
            isCharging: false,
            rawCurrentCapacity: 5000,
            rawMaxCapacity: 5800,
            amperage: 0,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        let powerSource = BatteryPowerSourceResolver.resolve(
            reportedPowerSource: .ac,
            registrySnapshot: snapshot,
            isCharging: false,
            previousPowerSource: .battery
        )

        #expect(powerSource == .ac)
    }

    @Test func recentBatteryStateWinsOverNegativeAmperageWhenAcConnects() {
        let snapshot = BatteryRegistrySnapshot(
            externalConnected: true,
            externalChargeCapable: true,
            isCharging: false,
            rawCurrentCapacity: 5000,
            rawMaxCapacity: 5800,
            amperage: -900,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        let powerSource = BatteryPowerSourceResolver.resolve(
            reportedPowerSource: .ac,
            registrySnapshot: snapshot,
            isCharging: false,
            previousPowerSource: .battery
        )

        #expect(powerSource == .ac)
    }
}
