import Foundation

enum BatteryTimeFormatter {
    static func format(minutes: Int) -> String {
        let clampedMinutes = max(1, minutes)
        let hours = clampedMinutes / 60
        let remainingMinutes = clampedMinutes % 60

        if hours == 0 {
            return "\(remainingMinutes)m"
        }

        return "\(hours)h \(String(format: "%02d", remainingMinutes))m"
    }
}
