import Foundation

protocol ChargingWattagePreferenceStore: AnyObject {
    var showsChargingWattageInMenuBar: Bool { get set }
}

final class UserDefaultsChargingWattagePreferenceStore: ChargingWattagePreferenceStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "ShowChargingWattageInMenuBar"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    var showsChargingWattageInMenuBar: Bool {
        get { userDefaults.bool(forKey: key) }
        set { userDefaults.set(newValue, forKey: key) }
    }
}
