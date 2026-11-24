import XCTest
@testable import SwiftAgent


final class OperationsTests: XCTestCase {
    func testDurationValidation() throws {
        XCTAssertEqual(try ExecutionWindow.duration("4h"), 14400)
        for value in ["0h", "-1s", "nanm", "8d", "200h", "4"] {
            XCTAssertThrowsError(try ExecutionWindow.duration(value))
        }
    }
    func testNextLocalOccurrence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 5))!
        let deadline = try ExecutionWindow.until("04:00", now: now, calendar: calendar)
        XCTAssertEqual(deadline.timeIntervalSince(now), 23 * 3600)
        XCTAssertThrowsError(try ExecutionWindow.until("24:00"))
        XCTAssertThrowsError(try ExecutionWindow.until("4:00"))
    }

    func testLocalOccurrenceAcrossDaylightSavingTransitions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        let springStart = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 3, day: 8, hour: 0)))
        let springDeadline = try ExecutionWindow.until("02:30", now: springStart, calendar: calendar)
        let springExpected = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 3, day: 8, hour: 3)))
        XCTAssertEqual(springDeadline, springExpected)

        let autumnStart = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 1, hour: 0)))
        let autumnDeadline = try ExecutionWindow.until("01:30", now: autumnStart, calendar: calendar)
        // The first 01:30 is 90 elapsed minutes after midnight, before clocks fall back.
        XCTAssertEqual(autumnDeadline.timeIntervalSince(autumnStart), 90 * 60)
    }
}
