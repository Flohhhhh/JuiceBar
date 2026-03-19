import SwiftUI

@main
struct JuiceBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = BatteryMenuViewModel()

    private var menuBarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showsMenuBarItem },
            set: { _ in }
        )
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarVisibilityBinding) {
            MenuContentView(viewModel: viewModel)
        } label: {
            HStack(spacing: 4) {
                if viewModel.showsChargingBolt {
                    Image(systemName: "bolt.fill")
                        .imageScale(.small)
                }

                Text(viewModel.displayText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
