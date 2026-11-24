import Foundation

public enum ExecutionWindow {
    public static func duration(_ value: String) throws -> TimeInterval {
        let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600]
        guard let suffix = value.last, let multiplier = units[suffix],
              let number = Double(value.dropLast()), number.isFinite, number > 0,
              number * multiplier <= 604800 else {
            throw AgentError.message("Duration requires a positive number followed by s, m or h (maximum 7 days)")
        }
        return number * multiplier
    }

    /// Calendar matching uses local time, advances missing DST times, and selects the first repeated time.
    public static func until(_ value: String, now: Date = Date(), calendar: Calendar = .current) throws -> Date {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute),
              let date = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute),
                                           matchingPolicy: .nextTime, repeatedTimePolicy: .first) else {
            throw AgentError.message("--until requires local time HH:MM")
        }
        return date
    }
}
