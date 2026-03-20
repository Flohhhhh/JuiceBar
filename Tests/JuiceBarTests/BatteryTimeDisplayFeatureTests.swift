import Foundation
import Testing
@testable import JuiceBar

struct BatteryTimeDisplayFeatureTests {
    @Test func absoluteFormatterUsesEstimateDateAsReference() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let estimateDate = Date(timeIntervalSince1970: 1_710_000_000)
        let expectedDate = estimateDate.addingTimeInterval(Double(80 * 60))

        let formatted = BatteryTimeFormatter.formatAbsolute(
            minutes: 80,
            estimateDate: estimateDate,
            locale: locale,
            timeZone: timeZone
        )

        #expect(formatted == expectedClockTime(for: expectedDate, locale: locale, timeZone: timeZone))
    }

    @Test func absoluteFormatterFallsBackToNowWhenEstimateDateIsMissing() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let expectedDate = now.addingTimeInterval(Double(45 * 60))

        let formatted = BatteryTimeFormatter.formatAbsolute(
            minutes: 45,
            estimateDate: nil,
            now: now,
            locale: locale,
            timeZone: timeZone
        )

        #expect(formatted == expectedClockTime(for: expectedDate, locale: locale, timeZone: timeZone))
    }

    @MainActor
    @Test func menuBarStaysRelativeWhilePanelShowsAbsoluteTime() {
        let estimateDate = Date(timeIntervalSince1970: 1_710_000_000)
        let viewModel = makeViewModel(
            state: BatteryState(
                hasBattery: true,
                percentage: 76,
                isCharging: false,
                isFull: false,
                powerSource: .battery,
                timeRemainingMinutes: 80,
                estimateDate: estimateDate,
                estimateSource: .system
            )
        )

        viewModel.refresh()

        let expectedTime = BatteryTimeFormatter.formatAbsolute(minutes: 80, estimateDate: estimateDate)

        #expect(viewModel.displayText == "1h 20m")
        #expect(viewModel.headlineText == "1h 20m remaining")
        #expect(viewModel.absoluteTimeText == "Runs out at \(expectedTime)")
    }

    @MainActor
    @Test func chargingPanelShowsAbsoluteFullTimeWhileMenuBarStaysRelative() {
        let estimateDate = Date(timeIntervalSince1970: 1_710_000_000)
        let chargingWattageStore = MockChargingWattagePreferenceStore(showsChargingWattageInMenuBar: true)
        let viewModel = makeViewModel(
            state: BatteryState(
                hasBattery: true,
                percentage: 63,
                isCharging: true,
                isFull: false,
                powerSource: .ac,
                timeRemainingMinutes: 80,
                estimateDate: estimateDate,
                estimateSource: .system,
                chargingWatts: 23
            ),
            chargingWattagePreferenceStore: chargingWattageStore
        )

        viewModel.refresh()

        let expectedTime = BatteryTimeFormatter.formatAbsolute(minutes: 80, estimateDate: estimateDate)

        #expect(viewModel.displayText == "1h 20m 23W")
        #expect(viewModel.headlineText == "1h 20m to full")
        #expect(viewModel.absoluteTimeText == "Full at \(expectedTime)")
    }

    @MainActor
    @Test func fullAndUnavailableStatesHideAbsolutePanelLine() {
        let fullViewModel = makeViewModel(
            state: BatteryState(
                hasBattery: true,
                percentage: 100,
                isCharging: false,
                isFull: true,
                powerSource: .ac,
                timeRemainingMinutes: nil,
                estimateDate: nil,
                estimateSource: .none
            )
        )
        fullViewModel.refresh()

        #expect(fullViewModel.displayText == "Full")
        #expect(fullViewModel.headlineText == "Full")
        #expect(fullViewModel.absoluteTimeText == nil)

        let unavailableViewModel = makeViewModel(
            state: BatteryState(
                hasBattery: true,
                percentage: 41,
                isCharging: false,
                isFull: false,
                powerSource: .battery,
                timeRemainingMinutes: nil,
                estimateDate: nil,
                estimateSource: .none
            )
        )
        unavailableViewModel.refresh()

        #expect(unavailableViewModel.displayText == "--")
        #expect(unavailableViewModel.headlineText == "Estimate unavailable")
        #expect(unavailableViewModel.absoluteTimeText == nil)
    }

    @MainActor
    @Test func pluggedInNotChargingHidesAbsolutePanelLine() {
        let viewModel = makeViewModel(
            state: BatteryState(
                hasBattery: true,
                percentage: 88,
                isCharging: false,
                isFull: false,
                powerSource: .ac,
                timeRemainingMinutes: nil,
                estimateDate: nil,
                estimateSource: .none
            )
        )

        viewModel.refresh()

        #expect(viewModel.headlineText == "Not charging")
        #expect(viewModel.absoluteTimeText == nil)
    }

    @MainActor
    private func makeViewModel(
        state: BatteryState,
        chargingWattagePreferenceStore: any ChargingWattagePreferenceStore = MockChargingWattagePreferenceStore(
            showsChargingWattageInMenuBar: false
        )
    ) -> BatteryMenuViewModel {
        BatteryMenuViewModel(
            batteryService: MockBatteryService(state: state),
            launchAtLoginService: LaunchAtLoginService(),
            chargingWattagePreferenceStore: chargingWattagePreferenceStore,
            autoRefresh: false
        )
    }

    private func expectedClockTime(for date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
