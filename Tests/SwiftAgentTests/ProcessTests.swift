import XCTest
@testable import SwiftAgent


final class ProcessTests: XCTestCase {
    private var directory: URL!
    private let commands = CommandRunner()

    override func setUpWithError() throws {
        Cancellation.requested = 0
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        Cancellation.requested = 0
        Cancellation.stopFile = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testOutputTruncationFlagAtCaptureLimit() throws {
        let commands = CommandRunner()
        let limit = 1_048_576
        for size in [limit, limit + 1] {
            let result = try commands.run("/bin/sh", ["-c", "head -c \(size) /dev/zero"],
                                          cwd: FileManager.default.temporaryDirectory)

            XCTAssertEqual(result.status, 0)
            XCTAssertFalse(result.timedOut)
            XCTAssertEqual(result.output.utf8.count, limit)
            XCTAssertEqual(result.outputTruncated, size > limit)
            XCTAssertTrue(result.outputIsUTF8)
        }
    }

    func testInvalidUTF8IsFlaggedDespiteReplacementDecoding() throws {
        let result = try CommandRunner().run("/bin/sh", ["-c", "printf 'before\\377after'"],
                                              cwd: FileManager.default.temporaryDirectory)

        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.outputTruncated)
        XCTAssertFalse(result.outputIsUTF8)
        XCTAssertEqual(result.output, "before\u{FFFD}after")
    }

    func testStopMarkerCancelsActiveCommand() throws {
        let marker = directory.appendingPathComponent("stop")
        try Data().write(to: marker)
        Cancellation.stopFile = marker
        defer { Cancellation.stopFile = nil }
        let start = Date()
        _ = try commands.run("/bin/sh", ["-c", "sleep 30"], cwd: directory)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testBackgroundChildrenCannotOutliveCommand() throws {
        let marker = directory.appendingPathComponent("leaked")
        let result = try commands.run("/bin/sh", ["-c", "(sleep 0.4; touch leaked) & exit 0"], cwd: directory)
        XCTAssertEqual(result.status, 0)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testTimeoutStopsCommand() throws {
        let start = Date()
        let result = try commands.run("/bin/sh", ["-c", "sleep 30"], cwd: directory, timeout: 0.05)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
