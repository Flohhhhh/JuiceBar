import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: BatteryMenuViewModel

    var body: some View {
        Group {
            Text(viewModel.headlineText)
                .monospacedDigit()

            Text("Battery: \(viewModel.percentageText)")
            Text("Status: \(viewModel.statusText)")

            if let note = viewModel.errorMessage ?? viewModel.launchAtLoginState.note {
                Divider()
                Text(note)
            }

            Divider()

            Button("Refresh") {
                viewModel.refresh()
            }

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                )
            )

            Divider()

            Button("Quit") {
                viewModel.quit()
            }
        }
    }
}
