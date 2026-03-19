import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: BatteryMenuViewModel

    var body: some View {
        Group {
            Section("JuiceBar") {
                Text(viewModel.headlineText)
                    .monospacedDigit()
                Text("\(viewModel.percentageText) battery")
            }

            Section("Info") {
                Text("Status: \(viewModel.statusText)")
                Text("Data Source: \(viewModel.dataSourceText)")
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
