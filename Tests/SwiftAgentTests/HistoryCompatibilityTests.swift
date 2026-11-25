import XCTest
@testable import SwiftAgent

final class HistoryCompatibilityTests: RepositoryTestCase {
    // Shape written before session/harness/timing metadata was required.
    private func legacyRecord() -> [String: Any] {
        ["id": "legacy-record", "repository": checkout.path, "branch": "swift-agent/project",
         "started": 0, "outcome": "no_candidate", "paths": [], "baselineChecks": [], "checks": []]
    }

    private func decode(_ object: [String: Any]) throws -> Record {
        try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testMissingAndNullLegacyMetadataUsesStableDefaults() throws {
        for null in [false, true] {
            var object = legacyRecord()
            if null {
                for key in ["sessionID", "harness", "terminal", "phaseSeconds"] { object[key] = NSNull() }
            }
            let record = try decode(object)
            XCTAssertEqual(record.sessionID, record.id)
            XCTAssertEqual(record.harness, "unknown")
            XCTAssertFalse(record.terminal)
            XCTAssertTrue(record.phaseSeconds.isEmpty)
            let encoded = try JSONEncoder().encode(record)
            let normalized = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(normalized["sessionID"] as? String, "legacy-record")
            XCTAssertEqual(normalized["harness"] as? String, "unknown")
            XCTAssertEqual(normalized["terminal"] as? Bool, false)
            XCTAssertNotNil(normalized["phaseSeconds"] as? [String: Double])
        }
    }

    func testCurrentMetadataAndHistoryPayloadSurviveRoundTrip() throws {
        var object = legacyRecord()
        object.merge(["sessionID": "session", "harness": "codex", "terminal": true,
                      "phaseSeconds": ["Harness": 1.25], "finished": 2, "phase": "Cleanup",
                      "baseline": "base", "commit": "tip", "task": "Improve fixture",
                      "paths": ["value.txt"], "detail": "Recorded detail",
                      "checks": [["command": "true", "status": 0, "output": "ok"]],
                      "baselineChecks": [["command": "false", "status": 1, "output": "before"]]]) { _, new in new }
        let record = try decode(object)
        let roundTrip = try JSONDecoder().decode(Record.self, from: JSONEncoder().encode(record))
        let encoded = try JSONEncoder().encode(roundTrip)
        let actual = try JSONSerialization.jsonObject(with: encoded) as! NSDictionary
        XCTAssertEqual(actual, object as NSDictionary)
    }

    func testMalformedMetadataAndMissingRequiredFieldsStillFail() throws {
        for key in ["sessionID", "harness", "terminal", "phaseSeconds"] {
            var object = legacyRecord()
            object[key] = ["invalid"]
            XCTAssertThrowsError(try decode(object), key)
        }
        for key in ["id", "repository", "branch", "started", "outcome"] {
            var object = legacyRecord()
            object.removeValue(forKey: key)
            XCTAssertThrowsError(try decode(object), key)
        }
    }

    func testLegacyHistorySupportsStatusPromptAndContinuedRuns() throws {
        let store = try StateStore(repository: Repository(at: checkout), dataDirectory: data)
        let bytes = try JSONSerialization.data(withJSONObject: legacyRecord())
        try bytes.write(to: store.directory.appendingPathComponent("legacy-record.json"))
        try bytes.write(to: store.directory.appendingPathComponent("latest.json"))
        let runner = Runner(agent: .testAgent)
        XCTAssertEqual(try runner.status(at: checkout, dataDirectory: data)?.sessionID, "legacy-record")
        XCTAssertEqual(try runner.history(at: checkout, dataDirectory: data).map(\.id), ["legacy-record"])
        XCTAssertFalse(try runner.prompt(at: checkout, dataDirectory: data).isEmpty)
        XCTAssertEqual(try run { _ in self.success() }.outcome, "no_candidate")
        XCTAssertEqual(try runner.history(at: checkout, dataDirectory: data).count, 2)
        // Reading completed history must not rewrite the original record.
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("legacy-record.json")), bytes)
    }

    func testLegacyInterruptedRecordIsRecoveredBeforeContinuedRun() throws {
        let store = try StateStore(repository: Repository(at: checkout), dataDirectory: data)
        var object = legacyRecord()
        object["outcome"] = "running"
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: store.directory.appendingPathComponent("legacy-record.json"))
        try bytes.write(to: store.directory.appendingPathComponent("latest.json"))
        XCTAssertEqual(try run { _ in self.success() }.outcome, "no_candidate")
        let recovered = try JSONDecoder().decode(Record.self,
            from: Data(contentsOf: store.directory.appendingPathComponent("legacy-record.json")))
        XCTAssertEqual(recovered.outcome, "interrupted")
        XCTAssertEqual(recovered.sessionID, "legacy-record")
        XCTAssertEqual(recovered.harness, "unknown")
        XCTAssertNotNil(recovered.finished)
    }
}
