import Foundation

public protocol HarnessAdapter {
    var name: String { get }
    func detect(in directory: URL) throws
    func run(prompt: String, cwd: URL, timeout: TimeInterval) throws -> CommandResult
}

/// Each invocation is a new process; custom arguments never pass through a shell.
struct CommandAdapter: HarnessAdapter {
    public let name: String
    let arguments: [String]
    let helpArguments: [String]?
    let requiredFlags: [String]?
    let capturesFinalMessage: Bool
    public init(name: String, arguments: [String], helpArguments: [String]? = nil,
                requiredFlags: [String]? = nil, capturesFinalMessage: Bool = false) {
        self.name = name
        self.arguments = arguments
        self.helpArguments = helpArguments
        self.requiredFlags = requiredFlags
        self.capturesFinalMessage = capturesFinalMessage
    }
    public func detect(in directory: URL) throws {
        if name == "custom" {
            let executable = arguments[0]
            let paths = executable.hasPrefix("/") ? [executable] :
                (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
                    .map { String($0) + "/" + executable }
            guard paths.contains(where: FileManager.default.isExecutableFile(atPath:)) else {
                throw AgentError.message("Cannot find custom executable: \(executable)")
            }
            return
        }
        let probe = helpArguments ?? [name, "--help"]
        let result = try CommandRunner().run("/usr/bin/env", probe, cwd: directory, timeout: 10)
        let flags = requiredFlags ?? arguments.dropFirst().filter { $0.hasPrefix("--") }
        guard result.status == 0, flags.allSatisfy(result.output.contains) else {
            throw AgentError.message("Install a compatible \(name) CLI supporting \(arguments.dropFirst().joined(separator: " "))")
        }
    }
    public func run(prompt: String, cwd: URL, timeout: TimeInterval) throws -> CommandResult {
        let message = capturesFinalMessage ? FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-agent-" + name + "-" + UUID().uuidString) : nil
        defer { if let message { try? FileManager.default.removeItem(at: message) } }
        let expanded = arguments.map { argument in
            argument.components(separatedBy: "{prompt}").map { part in
                let value = part.replacingOccurrences(of: "{cwd}", with: cwd.path)
                return message.map { value.replacingOccurrences(of: "{output}", with: $0.path) } ?? value
            }.joined(separator: prompt)
        }
        let result = try CommandRunner().run("/usr/bin/env", expanded, cwd: cwd, timeout: timeout)
        guard let message, let final = try? String(contentsOf: message, encoding: .utf8) else { return result }
        return CommandResult(status: result.status, output: final, timedOut: result.timedOut)
    }
}

public enum Harnesses {
    public static var builtins: [any HarnessAdapter] { builtins(yolo: false) }

    public static func builtins(yolo: Bool, configuration: Configuration = Configuration()) -> [any HarnessAdapter] {
        let codex = yolo ? ["codex", "exec", "--dangerously-bypass-approvals-and-sandbox"] :
            ["codex", "--ask-for-approval", "never", "exec", "--sandbox", "workspace-write"]
        let codexFlags = yolo ? ["--dangerously-bypass-approvals-and-sandbox"] : ["--sandbox"]
        return [
            CommandAdapter(name: "codex", arguments: codex + ["--cd", "{cwd}", "--output-last-message", "{output}", "{prompt}"],
                helpArguments: ["codex", "--ask-for-approval", "never", "exec", "--help"],
                requiredFlags: codexFlags + ["--cd", "--output-last-message"], capturesFinalMessage: true),
            CommandAdapter(name: "claude", arguments: ["claude", "--print"] +
                (yolo ? ["--dangerously-skip-permissions"] : ["--permission-mode", "acceptEdits"]) + ["{prompt}"]),
            CommandAdapter(name: "pi", arguments: ["pi", "--print", "--no-session"] +
                (yolo ? ["--approve"] : []) + ["{prompt}"]),
            CommandAdapter(name: "opencode", arguments: ["opencode", "run"] +
                (yolo ? ["--auto"] : []) + ["{prompt}"], helpArguments: ["opencode", "run", "--help"]),
            CommandAdapter(name: "gemini", arguments: ["gemini", "--approval-mode", yolo ? "yolo" : "auto_edit", "--prompt", "{prompt}"],
                requiredFlags: ["--approval-mode", "--prompt", yolo ? "yolo" : "auto_edit"]),
            OllamaAdapter(configuration: configuration)]
    }
    public static func select(configuration: Configuration, directory: URL, yolo: Bool = false) throws -> any HarnessAdapter {
        try configuration.validate()
        let adapters = builtins(yolo: yolo, configuration: configuration)
        if configuration.harness == "custom" {
            guard !yolo else { throw AgentError.message("--yolo only supports built-in harnesses; configure customCommand explicitly for a custom harness") }
            guard let command = configuration.customCommand, let executable = command.first, !executable.isEmpty, !executable.hasPrefix("-"), !executable.contains("="), (executable.hasPrefix("/") || !executable.contains("/")), command.dropFirst().contains(where: { $0.contains("{prompt}") }) else { throw AgentError.message("customCommand requires an executable and {prompt} argument") }
            return CommandAdapter(name: "custom", arguments: command)
        }
        if let name = configuration.harness {
            guard let adapter = adapters.first(where: { $0.name == name }) else { throw AgentError.message("Unknown harness: \(name)") }
            return adapter
        }
        for adapter in adapters { if (try? adapter.detect(in: directory)) != nil { return adapter } }
        throw AgentError.message("Install Codex, Claude Code, Pi, OpenCode or Gemini, or configure Ollama or a custom harness")
    }
}
