import XCTest
@testable import SwiftAgent


final class HarnessTests: XCTestCase {
    func testFinalMessageCapturePreservesPromptAndCleansTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let adapter = CommandAdapter(name: "fixture", arguments: ["/bin/sh", "-c",
            "printf '%s' \"$1\" > \"$2\"; printf '%s' \"$2\" > output-path; printf 'noise'; exit 7",
            "fixture", "{prompt}", "{output}"], capturesFinalMessage: true)
        let prompt = "Keep {cwd}, {output}, {prompt}, '$HOME' and `literal` unchanged."
        let result = try adapter.run(prompt: prompt, cwd: directory, timeout: 5)
        XCTAssertEqual(result.output, prompt)
        XCTAssertEqual(result.status, 7)
        XCTAssertFalse(result.timedOut)
        let path = try String(contentsOf: directory.appendingPathComponent("output-path"), encoding: .utf8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testYoloDetectionRejectsUnsupportedFlag() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Use a harmless help probe representing an older CLI that lacks the bypass flag.
        let adapter = CommandAdapter(name: "fixture", arguments: ["fixture", "--print", "--auto", "{prompt}"],
            helpArguments: ["/bin/echo", "--print"])
        XCTAssertThrowsError(try adapter.detect(in: directory))
    }

    func testMissingFinalMessageFallsBackToCommandOutput() throws {
        let adapter = CommandAdapter(name: "fixture", arguments: ["/bin/sh", "-c",
            "printf 'fallback'; exit 3", "fixture", "{output}", "{prompt}"], capturesFinalMessage: true)
        let result = try adapter.run(prompt: "test", cwd: FileManager.default.temporaryDirectory, timeout: 5)
        XCTAssertEqual(result.output, "fallback")
        XCTAssertEqual(result.status, 3)
    }
}
