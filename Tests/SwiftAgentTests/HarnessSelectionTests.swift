import XCTest
@testable import SwiftAgent

final class HarnessSelectionTests: XCTestCase {
    func testBuiltInArgumentMappingsAndDetectionContracts() throws {
        for yolo in [false, true] {
            let expected: [(String, [String])] = [
                ("codex", (yolo ? ["codex", "exec", "--dangerously-bypass-approvals-and-sandbox"] :
                    ["codex", "--ask-for-approval", "never", "exec", "--sandbox", "workspace-write"]) +
                    ["--cd", "{cwd}", "--output-last-message", "{output}", "{prompt}"]),
                ("claude", ["claude", "--print"] + (yolo ? ["--dangerously-skip-permissions"] :
                    ["--permission-mode", "acceptEdits"]) + ["{prompt}"]),
                ("pi", ["pi", "--print", "--no-session"] + (yolo ? ["--approve"] : []) + ["{prompt}"]),
                ("opencode", ["opencode", "run"] + (yolo ? ["--auto"] : []) + ["{prompt}"]),
                ("gemini", ["gemini", "--approval-mode", yolo ? "yolo" : "auto_edit", "--prompt", "{prompt}"])
            ]
            var configuration = Configuration(agent: .testAgent)
            configuration.ollamaModel = "fixture-model"
            configuration.ollamaHost = "http://192.0.2.1:11434"
            let adapters = Harnesses.builtins(yolo: yolo, configuration: configuration)
            XCTAssertEqual(adapters.map(\.name), expected.map(\.0) + ["ollama"])
            for (name, arguments) in expected {
                configuration.harness = name
                let selected = try Harnesses.select(configuration: configuration, directory: FileManager.default.temporaryDirectory, yolo: yolo)
                let adapter = try XCTUnwrap(selected as? CommandAdapter)
                XCTAssertEqual(adapter.arguments, arguments, "\(name), yolo=\(yolo)")
                XCTAssertEqual(adapter.capturesFinalMessage, name == "codex")
                if name == "codex" {
                    XCTAssertEqual(adapter.helpArguments, ["codex", "--ask-for-approval", "never", "exec", "--help"])
                } else if name == "opencode" {
                    XCTAssertEqual(adapter.helpArguments, ["opencode", "run", "--help"])
                }
            }
            configuration.harness = "ollama"
            let selected = try XCTUnwrap(try Harnesses.select(configuration: configuration,
                directory: FileManager.default.temporaryDirectory, yolo: yolo) as? OllamaAdapter)
            XCTAssertEqual(selected.configuration.ollamaModel, "fixture-model")
            XCTAssertEqual(selected.configuration.ollamaHost, "http://192.0.2.1:11434")
        }
    }

    func testCustomSelectionAndInvalidCommandsDoNotLaunchProcesses() throws {
        var configuration = Configuration(agent: .testAgent)
        configuration.harness = "custom"
        let directory = FileManager.default.temporaryDirectory
        for command in [nil, [], [""], ["-flag", "{prompt}"], ["ENV=value", "{prompt}"],
                        ["relative/tool", "{prompt}"], ["tool", "missing prompt"]] as [[String]?] {
            configuration.customCommand = command
            XCTAssertThrowsError(try Harnesses.select(configuration: configuration, directory: directory))
        }
        for executable in ["fixture-command", "/nonexistent/fixture-command"] {
            configuration.customCommand = [executable, "{cwd}", "prefix:{prompt}"]
            let adapter = try XCTUnwrap(try Harnesses.select(configuration: configuration, directory: directory) as? CommandAdapter)
            XCTAssertEqual(adapter.arguments, configuration.customCommand)
            XCTAssertThrowsError(try adapter.detect(in: directory))
            XCTAssertThrowsError(try Harnesses.select(configuration: configuration, directory: directory, yolo: true))
        }
        configuration.harness = "unknown-fixture"
        XCTAssertThrowsError(try Harnesses.select(configuration: configuration, directory: directory))
    }
}
