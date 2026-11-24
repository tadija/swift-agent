import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct OllamaTools {
    let root: URL
    let protectedPaths: [String]
    let deadline: TimeInterval
    private let commands = CommandRunner()

    var schemas: [[String: Any]] {
        func tool(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String]) -> [String: Any] {
            ["type": "function", "function": ["name": name, "description": description,
                "parameters": ["type": "object", "properties": properties, "required": required, "additionalProperties": false]]]
        }
        let path: [String: String] = ["type": "string", "description": "Path relative to the worktree root"]
        let text: [String: String] = ["type": "string"]
        let result = [
            tool("list_files", "List Git-tracked and unignored files, optionally below a directory. Output is capped; use a narrower directory when truncated.", ["path": path], []),
            tool("read_file", "Read UTF-8 file lines (at most 1 MiB per file). Defaults to the first 200 lines; use start_line and line_count to page.",
                 ["path": path, "start_line": ["type": "integer"], "line_count": ["type": "integer"]], ["path"]),
            tool("search", "Search files for a literal, case-sensitive string, optionally below a directory. Returns up to 100 matching lines.", ["query": text, "path": path], ["query"]),
            tool("write_file", "Create or replace a UTF-8 file. Read existing files first; preserve unrelated content. No symlinks or protected paths.", ["path": path, "content": text], ["path", "content"]),
            tool("replace_text", "Replace exactly one occurrence of old_text in a UTF-8 file. Fails if missing or ambiguous.", ["path": path, "old_text": text, "new_text": text], ["path", "old_text", "new_text"])
        ]
        return result + [tool("run_command", "Execute a shell command in the worktree for Git inspection, builds, and tests. No filesystem sandbox; engine constraints still apply.", ["command": text], ["command"])]
    }

    func checkBudget() throws {
        guard !Cancellation.shouldStop else { throw AgentError.message("Ollama iteration cancelled") }
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw AgentError.message("Ollama iteration timed out") }
    }

    static func bounded(_ text: String) -> String {
        let data = Data(text.utf8)
        return data.count <= 32_768 ? text : String(decoding: data.prefix(32_768), as: UTF8.self) + "\n[truncated]"
    }

    func execute(_ name: String, arguments: [String: Any]) throws -> String {
        try checkBudget()
        func string(_ key: String) throws -> String {
            guard let value = arguments[key] as? String else { throw AgentError.message("Missing string argument: \(key)") }
            return value
        }
        switch name {
        case "list_files":
            return Self.bounded(try files(below: arguments["path"] as? String ?? ".").joined(separator: "\n"))
        case "read_file":
            let lines = try read(path: string("path")).components(separatedBy: "\n")
            let start = arguments["start_line"] as? Int ?? 1
            let count = arguments["line_count"] as? Int ?? 200
            guard start > 0, count > 0, count <= 1000 else { throw AgentError.message("Invalid line range (maximum 1000 lines)") }
            return Self.bounded(lines.dropFirst(start - 1).prefix(count).enumerated().map { "\(start + $0.offset): \($0.element)" }.joined(separator: "\n"))
        case "search":
            let query = try string("query")
            guard !query.isEmpty else { throw AgentError.message("Search query must not be empty") }
            var matches: [String] = []
            for path in try files(below: arguments["path"] as? String ?? ".") {
                try checkBudget()
                guard let content = try? read(path: path) else { continue }
                for (line, text) in content.components(separatedBy: "\n").enumerated() where text.contains(query) {
                    matches.append("\(path):\(line + 1): \(text)")
                    if matches.count >= 100 { return Self.bounded(matches.joined(separator: "\n") + "\n[100 match limit]") }
                }
            }
            return Self.bounded(matches.joined(separator: "\n"))
        case "write_file":
            try write(path: string("path"), content: string("content"))
            return "File written"
        case "replace_text":
            let path = try string("path")
            let old = try string("old_text")
            let new = try string("new_text")
            let content = try read(path: path)
            guard !old.isEmpty, content.components(separatedBy: old).count == 2 else {
                throw AgentError.message("old_text must match exactly once")
            }
            try write(path: path, content: content.replacingOccurrences(of: old, with: new))
            return "Text replaced"
        case "run_command":
            let result = try commands.run("/bin/sh", ["-c", try string("command")], cwd: root,
                                          timeout: max(0.001, deadline - ProcessInfo.processInfo.systemUptime))
            try checkBudget()
            return "Exit status: \(result.status)\n" + Self.bounded(result.output)
        default:
            throw AgentError.message("Unknown tool: \(name)")
        }
    }

    /// Refuse symlinks and traversal before touching a path, including missing files' parents.
    private func resolve(_ path: String, writing: Bool = false) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty, !path.hasPrefix("/"), !parts.contains(".."), !path.contains("\0") else {
            throw AgentError.message("Path must stay within the worktree")
        }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        var url = base
        for part in parts where !part.isEmpty && part != "." {
            let lower = part.lowercased()
            guard ![".git", "secrets", "credentials"].contains(lower), lower != ".env", !lower.hasPrefix(".env."),
                  !lower.hasSuffix(".pem"), !lower.hasSuffix(".key") else { throw AgentError.message("Restricted path: \(path)") }
            url.appendPathComponent(part)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw AgentError.message("Symlinks are not supported: \(path)")
            }
        }
        guard url.path == base.path || url.path.hasPrefix(base.path + "/") else { throw AgentError.message("Path escapes worktree") }
        if writing {
            guard url != base else { throw AgentError.message("Cannot write the worktree root") }
            let relative = String(url.path.dropFirst(base.path.count + 1))
            try ChangePolicy.validate(path: relative, protectedPaths: protectedPaths)
        }
        return url
    }

    private func files(below path: String) throws -> [String] {
        let directory = try resolve(path)
        let result = try commands.run("/usr/bin/env", ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd: root,
                                      timeout: max(0.001, deadline - ProcessInfo.processInfo.systemUptime))
        try checkBudget()
        guard result.status == 0, !result.outputTruncated, result.outputIsUTF8 else {
            throw AgentError.message("Cannot list worktree files (Git failed or output exceeded 1 MiB)")
        }
        return try Set(result.output.split(separator: "\0").map(String.init)).sorted().filter { path in
            try checkBudget()
            guard let url = try? resolve(path), url.path == directory.path || url.path.hasPrefix(directory.path + "/") else { return false }
            return !path.split(separator: "/").contains(where: { [".build", "node_modules", "dist", "build"].contains($0.lowercased()) })
        }
    }

    private func read(path: String) throws -> String {
        let url = try resolve(path)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else {
            throw AgentError.message("Expected a regular UTF-8 file of at most 1 MiB")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func write(path: String, content: String) throws {
        let url = try resolve(path, writing: true)
        guard content.utf8.count <= 1_048_576 else { throw AgentError.message("File exceeds 1 MiB") }
        let files = FileManager.default
        let attributes = try? files.attributesOfItem(atPath: url.path)
        if let attributes, attributes[.type] as? FileAttributeType != .typeRegular {
            throw AgentError.message("Can only overwrite regular files")
        }
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url, options: .atomic)
        if let permissions = attributes?[.posixPermissions] {
            try files.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }
}
