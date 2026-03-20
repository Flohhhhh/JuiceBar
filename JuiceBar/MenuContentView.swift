import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: BatteryMenuViewModel

    var body: some View {
        Group {
            Section("JuiceBar") {
                Text(viewModel.headlineText)
                    .monospacedDigit()
                if let absoluteTimeText = viewModel.absoluteTimeText {
                    Text(absoluteTimeText)
                }
                Text("\(viewModel.percentageText) battery")
            }

            Section("Info") {
                Text("Status: \(viewModel.statusText)")
                Text("Data Source: \(viewModel.dataSourceText)")
                if let chargingPowerText = viewModel.chargingPowerText {
                    Text(chargingPowerText)
                }
            }

            Divider()

            Button(
                viewModel.showsChargingWattageInMenuBar
                    ? "Hide Charging Wattage in Menu Bar"
                    : "Show Charging Wattage in Menu Bar"
            ) {
                viewModel.setShowsChargingWattageInMenuBar(!viewModel.showsChargingWattageInMenuBar)
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
