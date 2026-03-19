import Foundation
import Testing
@testable import JuiceBar

struct BatteryDischargeEstimateTrackerTests {
    private func makeIsolatedTracker() -> (BatteryDischargeEstimateTracker, UserDefaults, String) {
        let suiteName = "BatteryDischargeEstimateTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsBatteryDischargeRateStore(userDefaults: defaults)
        return (BatteryDischargeEstimateTracker(rateStore: store), defaults, suiteName)
    }

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

    @Test func cachedStableRateCanEstimateImmediatelyAfterReset() {
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
        let laterSnapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5100,
            rawMaxCapacity: 5800,
            amperage: -9000,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        #expect(tracker.recordAndEstimate(registrySnapshot: steadySnapshot, now: start) == nil)
        #expect(tracker.recordAndEstimate(registrySnapshot: steadySnapshot, now: start.addingTimeInterval(1)) == nil)
        #expect(tracker.recordAndEstimate(registrySnapshot: steadySnapshot, now: start.addingTimeInterval(2)) == 270)

        tracker.reset()

        #expect(tracker.estimateUsingCachedRate(registrySnapshot: laterSnapshot) == 255)
    }

    @Test func cachedRateIsUnavailableWithoutStableHistory() {
        let (tracker, defaults, suiteName) = makeIsolatedTracker()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
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
        _ = tracker.recordAndEstimate(registrySnapshot: snapshot, now: start.addingTimeInterval(1))
        tracker.reset()

        #expect(tracker.estimateUsingCachedRate(registrySnapshot: snapshot) == nil)
    }

    @Test func resolvedEstimateSeedsCachedRateImmediately() {
        let tracker = BatteryDischargeEstimateTracker()
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5100,
            rawMaxCapacity: 5800,
            amperage: -600,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        tracker.cacheResolvedEstimate(registrySnapshot: snapshot, minutes: 510)

        #expect(tracker.estimateUsingCachedRate(registrySnapshot: snapshot) == 510)
    }

    @Test func resolvedEstimateSeedDoesNotPersistAcrossTrackerInstances() {
        let suiteName = "BatteryDischargeEstimateTrackerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Expected isolated user defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsBatteryDischargeRateStore(userDefaults: defaults)
        let tracker = BatteryDischargeEstimateTracker(rateStore: store)
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5100,
            rawMaxCapacity: 5800,
            amperage: -600,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        tracker.cacheResolvedEstimate(registrySnapshot: snapshot, minutes: 510)

        let restoredTracker = BatteryDischargeEstimateTracker(rateStore: store)

        #expect(restoredTracker.estimateUsingCachedRate(registrySnapshot: snapshot) == nil)
    }

    @Test func implausibleResolvedEstimateDoesNotPoisonCachedRate() {
        let (tracker, defaults, suiteName) = makeIsolatedTracker()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5100,
            rawMaxCapacity: 5800,
            amperage: -106,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        tracker.cacheResolvedEstimate(registrySnapshot: snapshot, minutes: 1)

        #expect(tracker.estimateUsingCachedRate(registrySnapshot: snapshot) == nil)
    }

    @Test func persistedBaselinesSurviveAcrossTrackerInstances() {
        let suiteName = "BatteryDischargeEstimateTrackerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Expected isolated user defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsBatteryDischargeRateStore(userDefaults: defaults)
        let tracker = BatteryDischargeEstimateTracker(rateStore: store)
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
        let laterSnapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5100,
            rawMaxCapacity: 5800,
            amperage: -9000,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        _ = tracker.recordAndEstimate(registrySnapshot: steadySnapshot, now: start)
        _ = tracker.recordAndEstimate(registrySnapshot: steadySnapshot, now: start.addingTimeInterval(1))
        #expect(tracker.recordAndEstimate(registrySnapshot: steadySnapshot, now: start.addingTimeInterval(2)) == 270)

        let restoredTracker = BatteryDischargeEstimateTracker(rateStore: store)

        #expect(
            restoredTracker.estimateUsingCachedRate(
                registrySnapshot: laterSnapshot,
                now: start.addingTimeInterval(10)
            ) == 255
        )
    }

    @Test func longTermBaselineOutlivesShortTermBaseline() {
        let suiteName = "BatteryDischargeEstimateTrackerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Expected isolated user defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsBatteryDischargeRateStore(userDefaults: defaults)
        let tracker = BatteryDischargeEstimateTracker(rateStore: store)
        let start = Date()
        let snapshot = BatteryRegistrySnapshot(
            rawCurrentCapacity: 5400,
            rawMaxCapacity: 5800,
            amperage: -1200,
            instantAmperage: nil,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        _ = tracker.recordAndEstimate(registrySnapshot: snapshot, now: start)
        _ = tracker.recordAndEstimate(registrySnapshot: snapshot, now: start.addingTimeInterval(1))
        #expect(tracker.recordAndEstimate(registrySnapshot: snapshot, now: start.addingTimeInterval(2)) == 270)

        let restoredTracker = BatteryDischargeEstimateTracker(rateStore: store)

        #expect(
            restoredTracker.estimateUsingCachedRate(
                registrySnapshot: snapshot,
                now: start.addingTimeInterval(8 * 24 * 60 * 60)
            ) == 270
        )
    }
}
