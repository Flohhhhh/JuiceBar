import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: BatteryMenuViewModel

    var body: some View {
        Group {
            Text(viewModel.headlineText)
                .monospacedDigit()

            Text("Battery: \(viewModel.percentageText)")
            Text("Status: \(viewModel.statusText)")

            if viewModel.showsLaunchAtLoginSection {
                Divider()

                if viewModel.showsLaunchAtLoginControl {
                    Text("Launch at Login: \(viewModel.launchAtLoginStatusText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { viewModel.launchAtLoginEnabled },
                            set: { viewModel.setLaunchAtLogin($0) }
                        )
                    )
                }

                if let note = viewModel.launchAtLoginMessage {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Button("Refresh") {
                viewModel.refresh()
            }

            Button("Quit") {
                viewModel.quit()
            }
        }
    }
}
