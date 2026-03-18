import SwiftUI

@main
struct JuiceBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = BatteryMenuViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            Text(viewModel.displayText)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.menu)
    }
}
