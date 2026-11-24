import Foundation

public struct Repository {
    public let root: URL
    public let commonDirectory: URL
    let commands: CommandRunner

    public init(at directory: URL, commands: CommandRunner = CommandRunner()) throws {
        self.commands = commands
        func resolve(_ args: [String]) throws -> String {
            let result = try commands.run("/usr/bin/env", ["git"] + args, cwd: directory)
            guard result.status == 0 else { throw AgentError.message("Not a supported Git checkout: \(result.output)") }
            guard !result.outputTruncated, result.outputIsUTF8 else {
                throw AgentError.message("Git output exceeds the 1 MiB limit or is not valid UTF-8")
            }
            return result.output.hasSuffix("\n") ? String(result.output.dropLast()) : result.output
        }
        root = URL(fileURLWithPath: try resolve(["rev-parse", "--show-toplevel"])).standardizedFileURL.resolvingSymlinksInPath()
        let common = try resolve(["rev-parse", "--path-format=absolute", "--git-common-dir"])
        commonDirectory = URL(fileURLWithPath: common).standardizedFileURL.resolvingSymlinksInPath()
        _ = try git(["rev-parse", "--verify", "HEAD^{commit}"])
    }

    @discardableResult
    public func git(_ args: [String], at cwd: URL? = nil, environment: [String: String] = [:]) throws -> String {
        let result = try commands.run("/usr/bin/env", ["git", "-c", "core.hooksPath=/dev/null"] + args,
                                      cwd: cwd ?? root, environment: environment.merging(["GIT_TERMINAL_PROMPT": "0", "GIT_NO_REPLACE_OBJECTS": "1"]) { _, required in required }, cancellable: false)
        guard result.status == 0 else { throw AgentError.message("git \(args.first ?? ""): \(result.output)") }
        guard !result.outputTruncated, result.outputIsUTF8 else {
            throw AgentError.message("Git output exceeds the 1 MiB limit or is not valid UTF-8")
        }
        return result.output.trimmingCharacters(in: .newlines)
    }

    func ref(_ name: String) -> String? { try? git(["rev-parse", "--verify", name + "^{commit}"]) }
    func isAncestor(_ ancestor: String, _ descendant: String) -> Bool {
        (try? commands.run("/usr/bin/env", ["git", "merge-base", "--is-ancestor", ancestor, descendant],
                           cwd: root, environment: ["GIT_NO_REPLACE_OBJECTS": "1"]).status) == 0
    }
    func worktreeFields() throws -> [Substring] {
        try git(["worktree", "list", "--porcelain", "-z"]).split(separator: "\0")
    }
    func requireUncheckedOut(_ ref: String) throws {
        guard try !worktreeFields().contains("branch " + ref) else {
            throw AgentError.message("Target branch is checked out in a worktree; switch it away before running")
        }
    }
    func refs() throws -> String { try git(["for-each-ref", "--format=%(refname) %(objectname)"]) }
}
