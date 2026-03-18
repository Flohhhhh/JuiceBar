import Foundation

enum BatteryPowerSource {
    case ac
    case battery
    case ups
    case unknown
}

struct BatteryState: Equatable {
    var hasBattery: Bool
    var percentage: Int?
    var isCharging: Bool
    var isFull: Bool
    var powerSource: BatteryPowerSource
    var timeRemainingMinutes: Int?
}
