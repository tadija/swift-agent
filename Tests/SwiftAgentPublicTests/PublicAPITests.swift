import Foundation
import XCTest
import SwiftAgent

private struct DocumentationHarness: HarnessAdapter {
    let name = "documentation-fixture"
    let mission: String
    let path: String
    func detect(in directory: URL) throws {}
    func run(prompt: String, cwd: URL, timeout: TimeInterval) throws -> CommandResult {
        XCTAssertTrue(prompt.contains(mission))
        XCTAssertTrue(prompt.contains("Do not commit, push"))
        XCTAssertFalse(prompt.contains("correctness, reliability, warnings"))
        try Data("Documented example\n".utf8).write(to: cwd.appendingPathComponent(path))
        return CommandResult(status: 0, output: "Document the example", timedOut: false)
    }
}

final class PublicAPITests: XCTestCase {
    func testSpecializedAgentNeedsOnlyDefinitionAndConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let checkout = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CommandRunner()
        func git(_ args: [String]) throws -> String {
            let result = try commands.run("/usr/bin/env", ["git"] + args, cwd: checkout)
            XCTAssertEqual(result.status, 0, result.output)
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "Fixture"])
        _ = try git(["config", "user.email", "fixture@example.invalid"])
        try Data("Initial\n".utf8).write(to: checkout.appendingPathComponent("README.md"))
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "Initial"])
        let mission = "Improve one documentation example."
        let agent = AgentDefinition(name: "Documentation Agent", executableName: "doc-agent", mission: mission)
        var config = Configuration(agent: agent)
        config.verification = ["test -s README.md"]
        let runner = Runner(agent: agent)
        let state = root.appendingPathComponent("state")
        let records = try runner.runSession(at: checkout, configuration: config,
            harness: DocumentationHarness(mission: mission, path: "README.md"), dataDirectory: state)
        XCTAssertEqual(records.map(\.outcome), ["committed"])
        XCTAssertEqual(records.first?.branch, "doc-agent/project")
        XCTAssertEqual(try git(["show", "-s", "--format=%an <%ae>|%s", "doc-agent/project"]),
                       "Documentation Agent <doc-agent@localhost>|doc-agent: Document the example")
        XCTAssertEqual(try git(["status", "--porcelain"]), "")
        XCTAssertEqual(try runner.history(at: checkout, dataDirectory: state).count, 1)
        // A second run sees the accepted contents and creates no empty commit.
        XCTAssertEqual(try runner.run(at: checkout, configuration: config,
            harness: DocumentationHarness(mission: mission, path: "README.md"), dataDirectory: state).outcome, "no_candidate")
        // Product configuration is protected even for arbitrary agent names.
        XCTAssertEqual(try runner.run(at: checkout, configuration: config,
            harness: DocumentationHarness(mission: mission, path: "doc-agent.json"), dataDirectory: state).outcome, "rejected")
        XCTAssertEqual(try git(["rev-list", "--all", "--count"]), "2")
        // The generic engine has no embedded fallback or implicit specialized mission.
        XCTAssertThrowsError(try Runner().runSession(at: checkout, configuration: Configuration(),
            harness: DocumentationHarness(mission: mission, path: "README.md"), dataDirectory: root.appendingPathComponent("missing")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing").path))
    }
}
