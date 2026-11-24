import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An in-process agent: Ollama supplies tool calls; engine executes worktree tools.
struct OllamaAdapter: HarnessAdapter {
    let name = "ollama"
    let configuration: Configuration
    var request: (String, [String: Any], TimeInterval) throws -> [String: Any]

    init(configuration: Configuration) {
        self.configuration = configuration
        self.request = { endpoint, body, timeout in
            try OllamaHTTP.post(host: configuration.ollamaHost, endpoint: endpoint, body: body, timeout: timeout)
        }
    }

    func detect(in directory: URL) throws {
        guard let model = configuration.ollamaModel, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.message("Set ollamaModel in configuration or pass --ollama-model NAME (use an installed tool-capable model)")
        }
        let info = try request("api/show", ["model": model], 10)
        guard (info["capabilities"] as? [String])?.contains("tools") == true else {
            throw AgentError.message("Ollama model \(model) does not advertise tool support; choose a tool-capable model and update Ollama if needed")
        }
    }

    func run(prompt: String, cwd: URL, timeout: TimeInterval) throws -> CommandResult {
        guard let model = configuration.ollamaModel else { throw AgentError.message("Set ollamaModel or --ollama-model NAME") }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let tools = OllamaTools(root: cwd, protectedPaths: configuration.protectedPaths, deadline: deadline)
        var messages: [[String: Any]] = [
            ["role": "system", "content": "You are a coding agent in a tool-calling loop. Use the supplied tools to inspect and edit this checkout. Tool errors are recoverable: correct the arguments and retry. Finish with a concise explanation after completing your work. Use run_command for Git inspection, builds, and tests. The orchestrator also runs baseline and final verification independently."],
            ["role": "user", "content": prompt]
        ]
        do {
            for _ in 0..<configuration.ollamaMaxTurns {
                try tools.checkBudget()
                let response = try request("api/chat", ["model": model, "messages": messages, "tools": tools.schemas,
                                                         "stream": false, "options": ["num_ctx": configuration.ollamaContextLength]],
                                           max(0.001, deadline - ProcessInfo.processInfo.systemUptime))
                try tools.checkBudget()
                guard response["done"] as? Bool == true,
                      let message = response["message"] as? [String: Any], message["role"] as? String == "assistant" else {
                    throw AgentError.message("Ollama returned an incomplete or invalid chat response")
                }
                messages.append(message) // Preserve thinking and tool calls for subsequent turns.
                if let rawCalls = message["tool_calls"], !(rawCalls is [[String: Any]]) {
                    throw AgentError.message("Ollama returned invalid tool calls")
                }
                let calls = message["tool_calls"] as? [[String: Any]] ?? []
                if calls.isEmpty {
                    guard let content = message["content"] as? String,
                          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw AgentError.message("Ollama returned neither tool calls nor a final response")
                    }
                    return CommandResult(status: 0, output: content, timedOut: false)
                }
                guard calls.count <= 16 else { throw AgentError.message("Ollama requested more than 16 tools in one turn") }
                for call in calls {
                    try tools.checkBudget()
                    guard let function = call["function"] as? [String: Any], let name = function["name"] as? String,
                          let arguments = function["arguments"] as? [String: Any] else {
                        throw AgentError.message("Ollama returned a malformed tool call")
                    }
                    let output: String
                    do { output = try tools.execute(name, arguments: arguments) }
                    catch {
                        try tools.checkBudget()
                        output = "Tool error: \(error)"
                    }
                    messages.append(["role": "tool", "tool_name": name, "content": OllamaTools.bounded(output)])
                }
            }
            return CommandResult(status: 1, output: "Ollama exceeded ollamaMaxTurns (\(configuration.ollamaMaxTurns)) without finishing", timedOut: false)
        } catch {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                return CommandResult(status: 1, output: "Ollama iteration timed out", timedOut: true)
            }
            throw error
        }
    }
}

enum OllamaHTTP {
    /// Accessed only before signal()/after wait() on the semaphore.
    private final class Reply: @unchecked Sendable {
        var data: Data?
        var response: URLResponse?
        var error: Error?
    }

    static func post(host: String, endpoint: String, body: [String: Any], timeout: TimeInterval, configuration: URLSessionConfiguration = .ephemeral) throws -> [String: Any] {
        guard let base = URL(string: host), ["http", "https"].contains(base.scheme), base.host != nil else {
            throw AgentError.message("ollamaHost must be an HTTP(S) URL")
        }
        var request = URLRequest(url: base.appendingPathComponent(endpoint), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let reply = Reply()
        let ready = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            reply.data = data
            reply.response = response
            reply.error = error
            ready.signal()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        task.resume()
        while ready.wait(timeout: .now() + 0.05) == .timedOut {
            if Cancellation.shouldStop { task.cancel(); throw AgentError.message("Ollama request cancelled") }
            if ProcessInfo.processInfo.systemUptime >= deadline { task.cancel(); throw AgentError.message("Ollama request timed out") }
        }
        if let error = reply.error { throw AgentError.message("Cannot reach Ollama at \(host): \(error.localizedDescription)") }
        guard let data = reply.data, data.count <= 4_194_304,
              let response = reply.response as? HTTPURLResponse else {
            throw AgentError.message("Ollama returned an invalid or oversized response")
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AgentError.message("Ollama returned invalid JSON at \(endpoint); set ollamaHost to the server base URL (for example http://192.168.1.50:11434)")
        }
        guard (200..<300).contains(response.statusCode), object["error"] == nil else {
            throw AgentError.message("Ollama HTTP \(response.statusCode): \(String(describing: object["error"] ?? "request failed"))")
        }
        return object
    }
}
