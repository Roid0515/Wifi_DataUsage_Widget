import Foundation

public enum UsageByteFormatter {
    public static func string(
        from bytes: UInt64,
        preference: UnitPreference = .automatic
    ) -> String {
        let divisor: Double
        let suffix: String

        switch preference {
        case .megabytes:
            divisor = 1_000_000
            suffix = "MB"
        case .gigabytes:
            divisor = 1_000_000_000
            suffix = "GB"
        case .automatic:
            switch bytes {
            case 0..<1_000:
                return "\(bytes) B"
            case 1_000..<1_000_000:
                divisor = 1_000
                suffix = "KB"
            case 1_000_000..<1_000_000_000:
                divisor = 1_000_000
                suffix = "MB"
            default:
                divisor = 1_000_000_000
                suffix = "GB"
            }
        }

        let value = Double(bytes) / divisor
        let digits: Int
        if value >= 100 {
            digits = 0
        } else if value >= 10 {
            digits = 1
        } else {
            digits = 2
        }
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(suffix)"
    }
}

public enum SessionDurationFormatter {
    public static func string(from startDate: Date?, to endDate: Date = Date()) -> String? {
        guard let startDate else { return nil }
        let seconds = max(0, Int(endDate.timeIntervalSince(startDate)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
