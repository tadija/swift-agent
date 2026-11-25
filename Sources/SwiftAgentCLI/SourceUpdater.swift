import Foundation
import SwiftAgent
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Explicit trust in a source repository whose build scripts will execute locally.
public struct SourceUpdateConfiguration: Sendable {
    public let repository: String
    public let reference: String

    /// Defaults to the main branch. A branch, tag or commit is accepted.
    public init(repository: String, reference: String = "main") throws {
        guard let url = URL(string: repository),
              ["https", "ssh", "file"].contains(url.scheme ?? ""),
              (url.isFileURL ? url.path.hasPrefix("/") : url.host?.isEmpty == false),
              !repository.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw AgentError.message("Update repository must be an absolute https, ssh or file URL")
        }
        guard !reference.isEmpty, !reference.hasPrefix("-"),
              !reference.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            throw AgentError.message("Update reference must be a nonempty branch, tag or commit without whitespace or a leading hyphen")
        }
        self.repository = repository
        self.reference = reference
    }
}

/// Source installation belongs to CLI infrastructure, never the agent runtime or build plugins.
public struct SourceUpdater {
    public let configuration: SourceUpdateConfiguration
    public let agent: AgentDefinition

    public init(configuration: SourceUpdateConfiguration, agent: AgentDefinition) {
        self.configuration = configuration
        self.agent = agent
    }

    public func update(executable: URL, onProgress: (String) -> Void = { _ in }) throws {
        let runner = CommandRunner()
        try update(executable: executable, onProgress: onProgress) { args, cwd in
            try runner.run("/usr/bin/env", args, cwd: cwd)
        }
    }

    // Process seam keeps failure and filesystem tests deterministic without network access.
    func update(executable: URL, onProgress: (String) -> Void = { _ in },
                replace: (String, String) -> Int32 = { rename($0, $1) },
                run: ([String], URL) throws -> CommandResult) throws {
        let files = FileManager.default
        let destination = executable.resolvingSymlinksInPath().standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        let path = destination.path
        // Known managed stores must be updated through their package manager, including symlink targets.
        guard !["/opt/homebrew/", "/usr/local/Cellar/", "/usr/local/Caskroom/", "/nix/", "/snap/", "/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/", "/opt/local/"].contains(where: path.hasPrefix),
              !path.contains("/.build/"), !path.contains("/Cellar/"), !path.contains("/Caskroom/") else {
            throw AgentError.message("Use the installation's package manager or installer to update \(path)")
        }
        let original = try files.attributesOfItem(atPath: path)
        guard original[.type] as? FileAttributeType == .typeRegular,
              let permissions = original[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o111 != 0, permissions.intValue & 0o6000 == 0 else {
            throw AgentError.message("Update destination must be an ordinary executable without setuid/setgid permissions")
        }
        guard files.isWritableFile(atPath: parent.path) else {
            throw AgentError.message("Cannot write installation directory \(parent.path); use its installer (no privileges are elevated)")
        }
        // Keep this inode permanently: unlinking a flock file would permit two independent locks.
        let lockPath = parent.appendingPathComponent(".\(destination.lastPathComponent)-update.lock").path
        let lock = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw AgentError.message("Cannot open update lock at \(lockPath): \(String(cString: strerror(errno)))") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            throw AgentError.message("Another update is targeting \(path); retry after it finishes")
        }
        defer { _ = flock(lock, LOCK_UN) }
        let temporary = files.temporaryDirectory.appendingPathComponent("swift-agent-update-" + UUID().uuidString)
        try files.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("source")
        func checkCancellation() throws {
            guard !Cancellation.shouldStop else { throw AgentError.message("Update cancelled") }
        }
        func checked(_ arguments: [String], at directory: URL) throws -> String {
            try checkCancellation()
            let result = try run(arguments, directory)
            try checkCancellation()
            guard result.status == 0, !result.timedOut else {
                throw AgentError.message("Update failed (\(arguments.prefix(2).joined(separator: " "))):\n\(result.output)")
            }
            guard !result.outputTruncated, result.outputIsUTF8 else {
                throw AgentError.message("Update command output is truncated or not UTF-8")
            }
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        onProgress("Fetching \(agent.name) source (\(configuration.reference))…")
        _ = try checked(["git", "clone", "--no-checkout", "--", configuration.repository, source.path], at: temporary)
        // Fetch the configured ref explicitly; non-default branches must not depend on local tracking refs.
        _ = try checked(["git", "fetch", "--", "origin", configuration.reference], at: source)
        // Explicit refs/heads and refs/tags disambiguate branch/tag collisions.
        let revision = try checked(["git", "rev-parse", "--verify", "--end-of-options", "FETCH_HEAD^{commit}"], at: source)
        guard revision.range(of: "^[0-9a-f]{40}([0-9a-f]{24})?$", options: .regularExpression) != nil else {
            throw AgentError.message("Git returned an invalid source revision")
        }
        _ = try checked(["git", "checkout", "--detach", revision], at: source)
        onProgress("Building release product \(agent.executableName)…")
        _ = try checked(["swift", "build", "-c", "release", "--product", agent.executableName], at: source)
        let buildPath = try checked(["swift", "build", "-c", "release", "--show-bin-path"], at: source)
        guard buildPath.hasPrefix("/"), !buildPath.contains("\n"), !buildPath.contains("\r") else {
            throw AgentError.message("Swift returned an invalid build directory")
        }
        let artifact = URL(fileURLWithPath: buildPath).appendingPathComponent(agent.executableName)
        let attributes = try files.attributesOfItem(atPath: artifact.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              files.isExecutableFile(atPath: artifact.path), (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
            throw AgentError.message("Build did not produce a regular executable for \(agent.executableName)")
        }
        let staged = parent.appendingPathComponent(".\(agent.executableName)-update-" + UUID().uuidString)
        defer { try? files.removeItem(at: staged) }
        try files.copyItem(at: artifact, to: staged)
        try files.setAttributes([.posixPermissions: permissions.intValue & 0o777], ofItemAtPath: staged.path)
        let version = try checked([staged.path, "--version"], at: temporary)
        let prefix = agent.name + " "
        guard version.hasPrefix(prefix), version.count > prefix.count, !version.contains("\n"), !version.contains("\r") else {
            throw AgentError.message("Built executable did not report a \(agent.name) version")
        }
        try checkCancellation()
        let current = try files.attributesOfItem(atPath: path)
        guard current[.systemFileNumber] as? NSNumber == original[.systemFileNumber] as? NSNumber,
              current[.systemNumber] as? NSNumber == original[.systemNumber] as? NSNumber,
              current[.type] as? FileAttributeType == .typeRegular else {
            throw AgentError.message("Installation changed during update; retry using its installer")
        }
        // Same-filesystem rename preserves the existing executable on failure, even on Linux.
        guard replace(staged.path, path) == 0 else {
            throw AgentError.message("Cannot replace \(path): \(String(cString: strerror(errno)))")
        }
        onProgress("Installed \(version) (source \(revision)) at \(path)")
    }
}
