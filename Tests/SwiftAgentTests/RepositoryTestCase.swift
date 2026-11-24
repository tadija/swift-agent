import XCTest
@testable import SwiftAgent

struct FakeHarness: HarnessAdapter {
    let name = "fake"
    var action: (URL) throws -> CommandResult
    func detect(in directory: URL) throws {}
    func run(prompt: String, cwd: URL, timeout: TimeInterval) throws -> CommandResult { try action(cwd) }
}

class RepositoryTestCase: XCTestCase {
    var temporary: URL!
    var checkout: URL!
    var data: URL!
    let commands = CommandRunner()

    override func setUpWithError() throws {
        Cancellation.requested = 0
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("swift-agent-tests-" + UUID().uuidString)
        checkout = temporary.appendingPathComponent("project")
        data = temporary.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try git(["init", "-b", "main"])
        try git(["config", "user.name", "SwiftAgent Test"])
        try git(["config", "user.email", "test@example.invalid"])
        try write("value.txt", "before\n")
        try write("swift-agent.json", "{\"verification\":[\"test -s value.txt\"]}")
        try git(["add", "."])
        try git(["commit", "-m", "Initial"])
    }
    override func tearDownWithError() throws {
        Cancellation.requested = 0
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
    }
    func write(_ path: String, _ content: String, at root: URL? = nil) throws {
        try Data(content.utf8).write(to: (root ?? checkout).appendingPathComponent(path))
    }
    @discardableResult func git(_ arguments: [String], at root: URL? = nil) throws -> String {
        let result = try commands.run("/usr/bin/env", ["git"] + arguments, cwd: root ?? checkout, cancellable: false)
        guard result.status == 0 else { throw AgentError.message(result.output) }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func run(_ action: @escaping (URL) throws -> CommandResult) throws -> Record {
        try Runner(agent: .testAgent).run(at: checkout, harness: FakeHarness(action: action), dataDirectory: data)
    }
    func success() -> CommandResult { CommandResult(status: 0, output: "Correct the value fixture", timedOut: false) }
    func assertNoCommit() throws {
        XCTAssertEqual(try git(["rev-list", "--all", "--count"]), "1")
        XCTAssertFalse(try git(["branch", "--list"]).contains("swift-agent/"))
        XCTAssertEqual(try git(["worktree", "list", "--porcelain"]).components(separatedBy: "worktree ").count, 2)
    }

}

extension AgentDefinition {
    static let testAgent = AgentDefinition(name: "Swift Agent", executableName: "swift-agent",
                                          mission: "Improve one fixture with a verified change.")
}
