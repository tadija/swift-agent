import XCTest
@testable import SwiftAgent
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OllamaTests: RepositoryTestCase {
    func testAgentEditsThroughToolsAndRunnerVerifiesCommit() throws {
        var configuration = Configuration(agent: .testAgent)
        configuration.ollamaModel = "fixture"
        configuration.ollamaHost = "http://192.168.1.50:11434"
        configuration.verification = ["test \"$(cat value.txt)\" = after"]
        var adapter = OllamaAdapter(configuration: configuration)
        var turn = 0
        adapter.request = { endpoint, body, _ in
            XCTAssertEqual(body["model"] as? String, "fixture")
            if endpoint == "api/show" { return ["capabilities": ["completion", "tools"]] }
            XCTAssertEqual(endpoint, "api/chat")
            XCTAssertEqual(body["stream"] as? Bool, false)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
            XCTAssertTrue(tools.contains { ($0["function"] as? [String: Any])?["name"] as? String == "run_command" })
            turn += 1
            switch turn {
            case 1:
                return self.reply(calls: [self.call("list_files", [:]), self.call("read_file", ["path": "value.txt"]), self.call("run_command", ["command": "git diff --stat"])])
            case 2:
                XCTAssertTrue(messages.contains { ($0["content"] as? String)?.contains("1: before") == true })
                return self.reply(calls: [self.call("replace_text", ["path": "value.txt", "old_text": "before", "new_text": "after"])])
            default:
                XCTAssertEqual(messages.last?["tool_name"] as? String, "replace_text")
                XCTAssertTrue(messages.contains { $0["thinking"] as? String == "Inspect the fixture" })
                return self.reply(content: "Correct fixture value\nVerified via SwiftAgent.")
            }
        }
        let record = try Runner(agent: .testAgent).run(at: checkout, configuration: configuration, harness: adapter, dataDirectory: data)
        XCTAssertEqual(record.outcome, "committed", record.detail ?? "")
        XCTAssertEqual(record.checks.first?.status, 0)
        XCTAssertEqual(try git(["show", record.branch + ":value.txt"]), "after")
        XCTAssertEqual(try String(contentsOf: checkout.appendingPathComponent("value.txt"), encoding: .utf8), "before\n")
    }

    func testToolsRejectTraversalSymlinksSecretsAndProtectedWrites() throws {
        let tools = OllamaTools(root: checkout, protectedPaths: ["value.txt", "swift-agent.json"], deadline: ProcessInfo.processInfo.systemUptime + 10)
        let outside = temporary.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: checkout.appendingPathComponent("link"), withDestinationURL: temporary)
        for path in ["../outside.txt", outside.path, "link/outside.txt", ".git/config", ".env", "secrets/key"] {
            XCTAssertThrowsError(try tools.execute("read_file", arguments: ["path": path]), path)
            XCTAssertThrowsError(try tools.execute("write_file", arguments: ["path": path, "content": "bad"]), path)
        }
        for path in ["value.txt", "swift-agent.json", "Package.swift", ".github/workflows/ci.yml", "AGENTS.md"] {
            XCTAssertThrowsError(try tools.execute("write_file", arguments: ["path": path, "content": "bad"]), path)
        }
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "outside")
    }

    func testToolsSearchCreateReplaceAndPreserveExecutablePermissions() throws {
        let tools = OllamaTools(root: checkout, protectedPaths: [], deadline: ProcessInfo.processInfo.systemUptime + 10)
        _ = try tools.execute("write_file", arguments: ["path": "src/value.sh", "content": "echo before\n"])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: checkout.appendingPathComponent("src/value.sh").path)
        XCTAssertTrue(try tools.execute("search", arguments: ["query": "echo before", "path": "src"]).contains("src/value.sh:1:"))
        _ = try tools.execute("replace_text", arguments: ["path": "src/value.sh", "old_text": "before", "new_text": "after"])
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: checkout.appendingPathComponent("src/value.sh").path))
        XCTAssertThrowsError(try tools.execute("replace_text", arguments: ["path": "src/value.sh", "old_text": "before", "new_text": "after"]))
        let listing = try tools.execute("list_files", arguments: ["path": "src"])
        XCTAssertEqual(listing, "src/value.sh")
    }

    func testShellAndGitAreAvailableWithoutYoloInWorktree() throws {
        let tools = OllamaTools(root: checkout, protectedPaths: [], deadline: ProcessInfo.processInfo.systemUptime + 10)
        XCTAssertTrue(tools.schemas.contains { ($0["function"] as? [String: Any])?["name"] as? String == "run_command" })
        let git = try tools.execute("run_command", arguments: ["command": "git status --short"])
        XCTAssertTrue(git.contains("Exit status: 0"))
        let output = try tools.execute("run_command", arguments: ["command": "printf shell > shell.txt"])
        XCTAssertTrue(output.contains("Exit status: 0"))
        XCTAssertEqual(try String(contentsOf: checkout.appendingPathComponent("shell.txt"), encoding: .utf8), "shell")
    }

    func testModelErrorsTurnLimitAndMalformedMessagesCannotProduceCommit() throws {
        var configuration = Configuration(agent: .testAgent)
        configuration.ollamaModel = "fixture"
        configuration.ollamaMaxTurns = 1
        var adapter = OllamaAdapter(configuration: configuration)
        adapter.request = { _, _, _ in ["capabilities": ["completion"]] }
        XCTAssertThrowsError(try adapter.detect(in: checkout))
        adapter.request = { _, _, _ in self.reply(calls: [self.call("read_file", ["path": "value.txt"])]) }
        let exhausted = try adapter.run(prompt: "test", cwd: checkout, timeout: 10)
        XCTAssertEqual(exhausted.status, 1)
        adapter.request = { _, _, _ in ["message": ["role": "assistant", "content": "incomplete"]] }
        XCTAssertThrowsError(try adapter.run(prompt: "test", cwd: checkout, timeout: 10))
        adapter.request = { _, _, _ in self.reply(content: "") }
        XCTAssertThrowsError(try adapter.run(prompt: "test", cwd: checkout, timeout: 10))
    }

    func testUnfinishedAgentCannotPublishPartialEdits() throws {
        var configuration = Configuration(agent: .testAgent)
        configuration.ollamaModel = "fixture"
        configuration.ollamaMaxTurns = 1
        configuration.verification = []
        var adapter = OllamaAdapter(configuration: configuration)
        adapter.request = { endpoint, _, _ in
            if endpoint == "api/show" { return ["capabilities": ["tools"]] }
            return self.reply(calls: [self.call("write_file", ["path": "value.txt", "content": "partial edit"])])
        }
        let record = try Runner(agent: .testAgent).run(at: checkout, configuration: configuration, harness: adapter, dataDirectory: data)
        XCTAssertEqual(record.outcome, "harness_failed")
        try assertNoCommit()
        XCTAssertEqual(try String(contentsOf: checkout.appendingPathComponent("value.txt"), encoding: .utf8), "before\n")
    }

    func testToolErrorsAreReturnedToModelAndCanBeCorrected() throws {
        var configuration = Configuration(agent: .testAgent)
        configuration.ollamaModel = "fixture"
        var adapter = OllamaAdapter(configuration: configuration)
        var turn = 0
        adapter.request = { _, body, _ in
            turn += 1
            if turn == 1 { return self.reply(calls: [self.call("unknown_tool", [:])]) }
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertTrue((messages.last?["content"] as? String)?.contains("Unknown tool: unknown_tool") == true)
            return self.reply(content: "No candidate")
        }
        XCTAssertEqual(try adapter.run(prompt: "test", cwd: checkout, timeout: 10).status, 0)
    }

    func testTimeoutAndCancellationStopAgentTools() throws {
        var configuration = Configuration(agent: .testAgent)
        configuration.ollamaModel = "fixture"
        var adapter = OllamaAdapter(configuration: configuration)
        adapter.request = { _, _, _ in XCTFail("Should stop before HTTP request"); return [:] }
        XCTAssertTrue(try adapter.run(prompt: "test", cwd: checkout, timeout: -1).timedOut)
        Cancellation.requested = 1
        XCTAssertThrowsError(try adapter.run(prompt: "test", cwd: checkout, timeout: 10))
    }

    private func call(_ name: String, _ arguments: [String: Any]) -> [String: Any] {
        ["function": ["name": name, "arguments": arguments]]
    }
    private func reply(content: String = "", calls: [[String: Any]] = []) -> [String: Any] {
        ["done": true, "message": ["role": "assistant", "content": content, "thinking": "Inspect the fixture", "tool_calls": calls]]
    }
}
