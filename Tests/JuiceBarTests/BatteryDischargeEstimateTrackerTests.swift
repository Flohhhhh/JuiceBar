import Foundation
import Testing
@testable import JuiceBar

struct BatteryDischargeEstimateTrackerTests {
    @Test func requiresSeveralSamplesBeforeReturningEstimate() {
        let tracker = BatteryDischargeEstimateTracker()
        let start = Date()
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5400,
            rawMaxCapacity: 5800,
            amperage: -1500,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        #expect(tracker.recordAndEstimate(registrySnapshot: snapshot, now: start) == nil)
        #expect(tracker.recordAndEstimate(registrySnapshot: snapshot, now: start.addingTimeInterval(1)) == nil)
        #expect(tracker.recordAndEstimate(registrySnapshot: snapshot, now: start.addingTimeInterval(2)) == 216)
    }

    @Test func usesMedianDischargeRateToRejectSingleSpike() {
        let tracker = BatteryDischargeEstimateTracker()
        let start = Date()
        let steadySnapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5400,
            rawMaxCapacity: 5800,
            amperage: -1200,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )
        let spikeSnapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5400,
            rawMaxCapacity: 5800,
            amperage: -6000,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        #expect(tracker.recordAndEstimate(registrySnapshot: steadySnapshot, now: start) == nil)
        #expect(tracker.recordAndEstimate(registrySnapshot: spikeSnapshot, now: start.addingTimeInterval(1)) == nil)
        let estimate = tracker.recordAndEstimate(registrySnapshot: steadySnapshot, now: start.addingTimeInterval(2))

        #expect(estimate == 270)
    }

    @Test func resetClearsEarlierSamples() {
        let tracker = BatteryDischargeEstimateTracker()
        let start = Date()
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5400,
            rawMaxCapacity: 5800,
            amperage: -1500,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        _ = tracker.recordAndEstimate(registrySnapshot: snapshot, now: start)
        _ = tracker.recordAndEstimate(registrySnapshot: snapshot, now: start.addingTimeInterval(2))
        tracker.reset()

        #expect(tracker.recordAndEstimate(registrySnapshot: snapshot, now: start.addingTimeInterval(6)) == nil)
    }
}
