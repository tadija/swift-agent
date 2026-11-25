import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct RepositoryLock {
    let descriptor: Int32
    init(at url: URL) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw AgentError.message("Cannot open repository lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw AgentError.message("Another agent run holds this repository's lock")
        }
    }
    func release() { flock(descriptor, LOCK_UN); close(descriptor) }
}

public struct Check: Codable {
    public let command: String
    public let status: Int32
    public let output: String
}

public struct Record: Codable {
    public let id: String
    public let sessionID: String
    public let harness: String
    public internal(set) var terminal: Bool = false
    public let repository: String
    public let branch: String
    public let started: Date
    public var finished: Date?
    public var phase: String?
    public var phaseSeconds: [String: Double] = [:]
    public var outcome: String
    public var baseline: String?
    public var commit: String?
    public var task: String?
    public var paths: [String] = []
    public var baselineChecks: [Check] = []
    public var checks: [Check] = []
    public var detail: String?
}

extension Record {
    private enum CodingKeys: String, CodingKey {
        case id, sessionID, harness, terminal, repository, branch, started, finished, phase
        case phaseSeconds, outcome, baseline, commit, task, paths, baselineChecks, checks, detail
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        // Older history omitted these fields (or encoded null). Normalize on read
        // while keeping the current nonoptional API and encoded record format.
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID) ?? id
        harness = try values.decodeIfPresent(String.self, forKey: .harness) ?? "unknown"
        terminal = try values.decodeIfPresent(Bool.self, forKey: .terminal) ?? false
        phaseSeconds = try values.decodeIfPresent([String: Double].self, forKey: .phaseSeconds) ?? [:]
        repository = try values.decode(String.self, forKey: .repository)
        branch = try values.decode(String.self, forKey: .branch)
        started = try values.decode(Date.self, forKey: .started)
        finished = try values.decodeIfPresent(Date.self, forKey: .finished)
        phase = try values.decodeIfPresent(String.self, forKey: .phase)
        outcome = try values.decode(String.self, forKey: .outcome)
        baseline = try values.decodeIfPresent(String.self, forKey: .baseline)
        commit = try values.decodeIfPresent(String.self, forKey: .commit)
        task = try values.decodeIfPresent(String.self, forKey: .task)
        paths = try values.decode([String].self, forKey: .paths)
        baselineChecks = try values.decode([Check].self, forKey: .baselineChecks)
        checks = try values.decode([Check].self, forKey: .checks)
        detail = try values.decodeIfPresent(String.self, forKey: .detail)
    }
}

struct StateStore {
    let directory: URL
    init(repository: Repository, dataDirectory: URL?, agent: AgentDefinition = .generic) throws {
        // Hex encoding is stable and collision-free, unlike Swift's randomized Hasher.
        let identity = repository.commonDirectory.path.utf8.map { String(format: "%02x", $0) }.joined()
        // Split long identities into path components to respect filesystem component limits.
        let components = stride(from: 0, to: identity.count, by: 100).map { offset in
            String(identity.dropFirst(offset).prefix(100))
        }
        let environment = ProcessInfo.processInfo.environment
        let xdgData = environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        let base = dataDirectory ?? URL(fileURLWithPath: xdgData ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share").path).appendingPathComponent(agent.stateNamespace)
        directory = components.reduce(base.appendingPathComponent("repositories")) { $0.appendingPathComponent($1) }
        let statePath = Self.canonicalPath(for: directory)
        for field in try repository.worktreeFields() where field.hasPrefix("worktree ") {
            let checkout = URL(fileURLWithPath: String(field.dropFirst("worktree ".count)))
                .standardizedFileURL.resolvingSymlinksInPath().path
            guard statePath != checkout, !statePath.hasPrefix(checkout == "/" ? "/" : checkout + "/") else {
                throw AgentError.message("Agent data directory must be outside all repository worktrees")
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }
    private static func canonicalPath(for directory: URL) -> String {
        // Foundation can only resolve symlinks reliably on the existing prefix.
        let url = directory.standardizedFileURL
        var ancestor = url
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        return suffix.reversed().reduce(ancestor.resolvingSymlinksInPath()) {
            $0.appendingPathComponent($1)
        }.path
    }

    var latest: Record? {
        get throws {
            let url = directory.appendingPathComponent("latest.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
        }
    }
    func recent(branch: String) throws -> [Record] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !["latest.json", "branches.json"].contains($0.lastPathComponent) }
            .map { try JSONDecoder().decode(Record.self, from: Data(contentsOf: $0)) }
            .filter { $0.branch == branch }
            .sorted { $0.started > $1.started }.prefix(10).map { $0 }
    }
    func ownedBranches() throws -> [String: String] {
        let url = directory.appendingPathComponent("branches.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }
    func own(branch: String, commit: String) throws {
        var branches = try ownedBranches()
        branches[branch] = commit
        try JSONEncoder().encode(branches).write(to: directory.appendingPathComponent("branches.json"), options: .atomic)
    }
    func save(_ record: Record) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: directory.appendingPathComponent(record.id + ".json"), options: .atomic)
        try data.write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
    }
}
