import Testing
@testable import JuiceBar

struct LaunchAtLoginStateTests {
    @Test func enabledStateShowsOnStatus() {
        let state = LaunchAtLoginState(status: .enabled, note: nil)

        #expect(state.isControllable)
        #expect(state.isEnabled)
        #expect(state.toggleValue)
        #expect(state.statusText == "On")
    }

    @Test func approvalRequiredStateKeepsToggleOnButShowsPendingStatus() {
        let state = LaunchAtLoginState(status: .requiresApproval, note: nil)

        #expect(state.isControllable)
        #expect(!state.isEnabled)
        #expect(state.toggleValue)
        #expect(state.statusText == "Pending Approval")
    }

    @Test func disabledStateShowsOffStatus() {
        let state = LaunchAtLoginState(status: .disabled, note: nil)

        #expect(state.isControllable)
        #expect(!state.isEnabled)
        #expect(!state.toggleValue)
        #expect(state.statusText == "Off")
    }

    @Test func unavailableStateHidesControl() {
        let state = LaunchAtLoginState(status: .unavailableForBuild, note: nil)

        #expect(state.isVisible)
        #expect(!state.isControllable)
        #expect(!state.toggleValue)
        #expect(state.statusText == "Unavailable")
    }

    @Test func unsignedBuildStateHidesEntireFeature() {
        let state = LaunchAtLoginState(status: .hiddenForUnsignedBuild, note: nil)

        #expect(!state.isVisible)
        #expect(!state.isControllable)
        #expect(!state.toggleValue)
        #expect(state.statusText.isEmpty)
    }
}
