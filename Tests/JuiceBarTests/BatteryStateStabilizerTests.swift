import Foundation
import Testing
@testable import JuiceBar

struct BatteryStateStabilizerTests {
    @Test func reusesRecentEstimateWhenModeIsStable() {
        let estimateDate = Date()
        let previous = BatteryState(
            hasBattery: true,
            percentage: 57,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 143,
            estimateDate: estimateDate,
            estimateSource: .system
        )
        let fresh = BatteryState(
            hasBattery: true,
            percentage: 56,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: nil,
            estimateDate: nil,
            estimateSource: .none
        )

        let stabilized = BatteryStateStabilizer.stabilize(
            previous: previous,
            fresh: fresh,
            now: estimateDate.addingTimeInterval(30)
        )

        #expect(stabilized.timeRemainingMinutes == 143)
        #expect(stabilized.estimateDate == estimateDate)
        #expect(stabilized.isCharging == false)
    }

    @Test func doesNotReuseChargingEstimateAcrossUnplugTransition() {
        let estimateDate = Date()
        let previous = BatteryState(
            hasBattery: true,
            percentage: 64,
            isCharging: true,
            isFull: false,
            powerSource: .ac,
            timeRemainingMinutes: 113,
            estimateDate: estimateDate,
            estimateSource: .system
        )
        let fresh = BatteryState(
            hasBattery: true,
            percentage: 64,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: nil,
            estimateDate: nil,
            estimateSource: .none
        )

        let stabilized = BatteryStateStabilizer.stabilize(
            previous: previous,
            fresh: fresh,
            now: estimateDate.addingTimeInterval(5)
        )

        #expect(stabilized.timeRemainingMinutes == nil)
        #expect(stabilized.isCharging == false)
        #expect(stabilized.powerSource == .battery)
    }

    @Test func doesNotReuseDischargeEstimateAcrossPlugInTransition() {
        let estimateDate = Date()
        let previous = BatteryState(
            hasBattery: true,
            percentage: 64,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 113,
            estimateDate: estimateDate,
            estimateSource: .system
        )
        let fresh = BatteryState(
            hasBattery: true,
            percentage: 64,
            isCharging: false,
            isFull: false,
            powerSource: .ac,
            timeRemainingMinutes: nil,
            estimateDate: nil,
            estimateSource: .none
        )

        let stabilized = BatteryStateStabilizer.stabilize(
            previous: previous,
            fresh: fresh,
            now: estimateDate.addingTimeInterval(5)
        )

        #expect(stabilized.timeRemainingMinutes == nil)
        #expect(stabilized.powerSource == .ac)
    }

    @Test func smoothsDerivedEstimatesAcrossRefreshes() {
        let estimateDate = Date()
        let previous = BatteryState(
            hasBattery: true,
            percentage: 94,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 51,
            estimateDate: estimateDate,
            estimateSource: .derived
        )
        let fresh = BatteryState(
            hasBattery: true,
            percentage: 94,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 180,
            estimateDate: estimateDate.addingTimeInterval(2),
            estimateSource: .derived
        )

        let stabilized = BatteryStateStabilizer.stabilize(
            previous: previous,
            fresh: fresh,
            now: estimateDate.addingTimeInterval(2)
        )

        #expect(stabilized.timeRemainingMinutes == 148)
        #expect(stabilized.estimateSource == .derived)
    }

    @Test func hidesFreshDerivedOutlierInsteadOfSmoothingOrReusingPreviousEstimate() {
        let estimateDate = Date()
        let previous = BatteryState(
            hasBattery: true,
            percentage: 94,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 51,
            estimateDate: estimateDate,
            estimateSource: .derived
        )
        let fresh = BatteryState(
            hasBattery: true,
            percentage: 94,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 2_000,
            estimateDate: estimateDate.addingTimeInterval(2),
            estimateSource: .derived
        )

        let stabilized = BatteryStateStabilizer.stabilize(
            previous: previous,
            fresh: fresh,
            now: estimateDate.addingTimeInterval(2)
        )

        #expect(stabilized.timeRemainingMinutes == nil)
        #expect(stabilized.estimateSource == .none)
    }

    @Test func doesNotReusePreviousEstimateWhenPreviousValueIsOutsideSafetyWindow() {
        let estimateDate = Date()
        let previous = BatteryState(
            hasBattery: true,
            percentage: 57,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: 2_000,
            estimateDate: estimateDate,
            estimateSource: .system
        )
        let fresh = BatteryState(
            hasBattery: true,
            percentage: 56,
            isCharging: false,
            isFull: false,
            powerSource: .battery,
            timeRemainingMinutes: nil,
            estimateDate: nil,
            estimateSource: .none
        )

        let stabilized = BatteryStateStabilizer.stabilize(
            previous: previous,
            fresh: fresh,
            now: estimateDate.addingTimeInterval(30)
        )

        #expect(stabilized.timeRemainingMinutes == nil)
        #expect(stabilized.estimateSource == .none)
    }
}
