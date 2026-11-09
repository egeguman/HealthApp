import Foundation

nonisolated enum Format {
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((max(interval, 0) / 60).rounded())
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    static func strain(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func strainRange(_ range: ClosedRange<Double>) -> String {
        "\(strain(range.lowerBound))–\(strain(range.upperBound))"
    }

    static func whole(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// 0.123 → "12%"
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func signedTemperature(_ delta: Double) -> String {
        String(format: "%+.1f°C", delta)
    }

    static func thousands(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number)
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
