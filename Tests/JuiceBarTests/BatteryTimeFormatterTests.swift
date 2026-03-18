import Testing
@testable import JuiceBar

@Test func formatsHoursAndMinutes() {
    #expect(BatteryTimeFormatter.format(minutes: 222) == "3h 42m")
}

@Test func formatsMinutesOnly() {
    #expect(BatteryTimeFormatter.format(minutes: 42) == "42m")
}

@Test func clampsSubMinuteValues() {
    #expect(BatteryTimeFormatter.format(minutes: 0) == "1m")
}
