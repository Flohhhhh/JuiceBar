import Foundation
import Testing
@testable import JuiceBar

struct ChargingWattageFeatureTests {
    @Test func positiveChargingCurrentProducesRoundedWatts() {
        let snapshot = BatteryRegistrySnapshot(
            amperage: 2080,
            voltage: 11_262,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        let watts = BatteryChargingPowerResolver.resolve(
            registrySnapshot: snapshot,
            isCharging: true,
            isFull: false
        )

        #expect(watts == 23)
    }

    @Test func missingTelemetryDoesNotProduceWatts() {
        let missingVoltageSnapshot = BatteryRegistrySnapshot(
            amperage: 2080,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )
        let zeroAmperageSnapshot = BatteryRegistrySnapshot(
            amperage: 0,
            voltage: 11_262,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        #expect(
            BatteryChargingPowerResolver.resolve(
                registrySnapshot: missingVoltageSnapshot,
                isCharging: true,
                isFull: false
            ) == nil
        )
        #expect(
            BatteryChargingPowerResolver.resolve(
                registrySnapshot: zeroAmperageSnapshot,
                isCharging: true,
                isFull: false
            ) == nil
        )
    }

    @Test func negativeAmperageDoesNotProduceChargingWatts() {
        let snapshot = BatteryRegistrySnapshot(
            amperage: -2080,
            voltage: 11_262,
            timeRemainingMinutes: nil,
            averageTimeToFullMinutes: nil,
            averageTimeToEmptyMinutes: nil
        )

        let watts = BatteryChargingPowerResolver.resolve(
            registrySnapshot: snapshot,
            isCharging: true,
            isFull: false
        )

        #expect(watts == nil)
    }

    @MainActor
    @Test func menuShowsChargingPowerAndMenuBarRespectsToggle() {
        let batteryService = MockBatteryService(
            state: BatteryState(
                hasBattery: true,
                percentage: 63,
                isCharging: true,
                isFull: false,
                powerSource: .ac,
                timeRemainingMinutes: 80,
                estimateDate: Date(),
                estimateSource: .system,
                chargingWatts: 23
            )
        )
        let preferenceStore = MockChargingWattagePreferenceStore(showsChargingWattageInMenuBar: false)
        let viewModel = BatteryMenuViewModel(
            batteryService: batteryService,
            launchAtLoginService: LaunchAtLoginService(),
            chargingWattagePreferenceStore: preferenceStore,
            autoRefresh: false
        )

        viewModel.refresh()

        #expect(viewModel.chargingPowerText == "Charging Power: 23W")
        #expect(viewModel.displayText == "1h 20m")

        viewModel.setShowsChargingWattageInMenuBar(true)

        #expect(viewModel.displayText == "1h 20m 23W")
        #expect(preferenceStore.showsChargingWattageInMenuBar)
    }

    @MainActor
    @Test func nonChargingStatesDoNotShowChargingWattage() {
        let batteryService = MockBatteryService(
            state: BatteryState(
                hasBattery: true,
                percentage: 100,
                isCharging: false,
                isFull: true,
                powerSource: .ac,
                timeRemainingMinutes: nil,
                estimateDate: nil,
                estimateSource: .none,
                chargingWatts: 23
            )
        )
        let viewModel = BatteryMenuViewModel(
            batteryService: batteryService,
            launchAtLoginService: LaunchAtLoginService(),
            chargingWattagePreferenceStore: MockChargingWattagePreferenceStore(showsChargingWattageInMenuBar: true),
            autoRefresh: false
        )

        viewModel.refresh()

        #expect(viewModel.chargingPowerText == nil)
        #expect(viewModel.displayText == "Full")
    }
}

private final class MockBatteryService: BatteryStateService {
    var onPowerSourceChange: (() -> Void)?
    var state: BatteryState

    init(state: BatteryState) {
        self.state = state
    }

    func invalidateTransientEstimateState(reason: String) {}

    func fetchState() -> BatteryState {
        state
    }
}

private final class MockChargingWattagePreferenceStore: ChargingWattagePreferenceStore {
    var showsChargingWattageInMenuBar: Bool

    init(showsChargingWattageInMenuBar: Bool) {
        self.showsChargingWattageInMenuBar = showsChargingWattageInMenuBar
    }
}
