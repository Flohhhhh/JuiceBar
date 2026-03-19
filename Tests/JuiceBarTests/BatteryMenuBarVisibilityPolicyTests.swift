import Foundation
import Testing
@testable import JuiceBar

struct BatteryMenuBarVisibilityPolicyTests {
    @Test func acWithoutChargingEstimateHidesMenuBarItem() {
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

        #expect(BatteryMenuBarVisibilityPolicy.shouldShowItem(for: state) == false)
    }

    @Test func chargingWithoutEstimateHidesMenuBarItem() {
        let state = BatteryState(
            hasBattery: true,
            percentage: 72,
            isCharging: true,
            isFull: false,
            powerSource: .ac,
            timeRemainingMinutes: nil,
            estimateDate: nil,
            estimateSource: .none
        )

        #expect(BatteryMenuBarVisibilityPolicy.shouldShowItem(for: state) == false)
    }

    @Test func chargingWithEstimateShowsMenuBarItem() {
        let state = BatteryState(
            hasBattery: true,
            percentage: 72,
            isCharging: true,
            isFull: false,
            powerSource: .ac,
            timeRemainingMinutes: 31,
            estimateDate: Date(),
            estimateSource: .system
        )

        #expect(BatteryMenuBarVisibilityPolicy.shouldShowItem(for: state) == true)
    }

    @Test func batteryWithoutEstimateHidesMenuBarItemUntilEstimateArrives() {
        let state = BatteryState(
            hasBattery: true,
            percentage: 91,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: nil,
            estimateDate: nil,
            estimateSource: .derived
        )

        #expect(BatteryMenuBarVisibilityPolicy.shouldShowItem(for: state) == false)
    }

    @Test func batteryWithEstimateShowsMenuBarItem() {
        let state = BatteryState(
            hasBattery: true,
            percentage: 91,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 344,
            estimateDate: Date(),
            estimateSource: .derived
        )

        #expect(BatteryMenuBarVisibilityPolicy.shouldShowItem(for: state) == true)
    }
}
