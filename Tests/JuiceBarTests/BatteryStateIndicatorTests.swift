import Foundation
import Testing
@testable import JuiceBar

struct BatteryStateIndicatorTests {
    @Test func batteryWithoutEstimateShowsPendingIndicator() {
        let state = BatteryState(
            hasBattery: true,
            percentage: 94,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: nil,
            estimateDate: nil,
            estimateSource: .none
        )

        let indicator = BatteryStateIndicator.resolve(from: state)

        #expect(indicator == .pendingEstimate)
        #expect(indicator.iconName == "hourglass")
    }

    @Test func derivedBatteryEstimateShowsFallbackIndicator() {
        let state = BatteryState(
            hasBattery: true,
            percentage: 94,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 180,
            estimateDate: Date(),
            estimateSource: .derived
        )

        let indicator = BatteryStateIndicator.resolve(from: state)

        #expect(indicator == .dischargingDerived)
        #expect(indicator.label == "Fallback Estimate")
    }

    @Test func chargingStateShowsChargingIndicator() {
        let state = BatteryState(
            hasBattery: true,
            percentage: 72,
            isCharging: true,
            isFull: false,
            powerSource: .ac,
            timeRemainingMinutes: 35,
            estimateDate: Date(),
            estimateSource: .system
        )

        let indicator = BatteryStateIndicator.resolve(from: state)

        #expect(indicator == .charging)
        #expect(indicator.iconName == "bolt.fill")
    }

    @Test func acWithoutChargingShowsNotChargingIndicator() {
        let state = BatteryState(
            hasBattery: true,
            percentage: 82,
            isCharging: false,
            isFull: false,
            powerSource: .ac,
            timeRemainingMinutes: nil,
            estimateDate: nil,
            estimateSource: .none
        )

        let indicator = BatteryStateIndicator.resolve(from: state)

        #expect(indicator == .notCharging)
        #expect(indicator.label == "Not Charging")
    }
}
