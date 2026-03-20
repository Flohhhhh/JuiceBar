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

    static func formatAbsolute(
        minutes: Int,
        estimateDate: Date?,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let clampedMinutes = max(1, minutes)
        let referenceDate = estimateDate ?? now
        let targetDate = referenceDate.addingTimeInterval(Double(clampedMinutes * 60))
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: targetDate)
    }
}
