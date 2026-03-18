import SwiftUI

@main
struct JuiceBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = BatteryMenuViewModel()

    var body: some Scene {
        MenuBarExtra {
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
