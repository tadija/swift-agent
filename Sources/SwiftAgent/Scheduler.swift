import Foundation

/// Durable schedules with native scheduler installation files and a manual fallback.
public struct LocalSchedule: Codable {
    public let id: String
    public let repository: String
    public let executable: String
    public let at: String
    public let duration: String
    public let timezone: String
}

public struct Scheduler {
    public let directory: URL
    private let agent: AgentDefinition
    public init(dataDirectory: URL? = nil, agent: AgentDefinition = .generic) throws {
        self.agent = agent
        // Match StateStore: XDG requires ignoring relative base directories.
        let xdgData = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        let base = xdgData ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share").path
        directory = (dataDirectory ?? URL(fileURLWithPath: base).appendingPathComponent(agent.stateNamespace)).appendingPathComponent("schedules")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func list() throws -> [LocalSchedule] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(LocalSchedule.self, from: Data(contentsOf: $0)) }
            .sorted { $0.id < $1.id }
    }
    public func add(repository: URL, executable: String, at: String, duration: String) throws -> LocalSchedule {
        _ = try ExecutionWindow.until(at)
        _ = try ExecutionWindow.duration(duration)
        let repo = try Repository(at: repository)
        let schedule = LocalSchedule(id: UUID().uuidString.lowercased(), repository: repo.root.path,
                                     executable: executable, at: at, duration: duration, timezone: TimeZone.current.identifier)
        let stem = directory.appendingPathComponent(schedule.id)
        try JSONEncoder().encode(schedule).write(to: stem.appendingPathExtension("json"), options: .atomic)
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let environment = ProcessInfo.processInfo.environment
        let exports = ["PATH", "XDG_CONFIG_HOME", "XDG_DATA_HOME"].compactMap { key in
            environment[key].map { "export " + key + "=" + quote($0) + "\n" }
        }.joined()
        let script = "#!/bin/sh\n" + exports + "cd " + quote(repo.root.path) + " || exit 1\nexec " + quote(executable) + " run --duration " + quote(duration) + "\n"
        let scriptURL = stem.appendingPathExtension("sh")
        try Data(script.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        let parts = at.split(separator: ":").map { Int($0)! }
        #if os(macOS)
        let plist: [String: Any] = ["Label": "local." + agent.stateNamespace + "." + schedule.id,
            "ProgramArguments": ["/bin/sh", scriptURL.path],
            "StartCalendarInterval": ["Hour": parts[0], "Minute": parts[1]],
            "StandardOutPath": stem.appendingPathExtension("log").path,
            "StandardErrorPath": stem.appendingPathExtension("log").path]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: stem.appendingPathExtension("plist"), options: .atomic)
        #else
        // systemd quoting is separate from shell quoting.
        let escaped = scriptURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "%", with: "%%")
        try Data("[Service]\nType=oneshot\nExecStart=/bin/sh \"\(escaped)\"\n".utf8)
            .write(to: directory.appendingPathComponent("\(agent.stateNamespace)-\(schedule.id).service"), options: .atomic)
        try Data("[Timer]\nOnCalendar=*-*-* \(at):00\nPersistent=false\n[Install]\nWantedBy=timers.target\n".utf8)
            .write(to: directory.appendingPathComponent("\(agent.stateNamespace)-\(schedule.id).timer"), options: .atomic)
        #endif
        return schedule
    }
    public func remove(_ id: String) throws {
        guard try list().contains(where: { $0.id == id }) else { throw AgentError.message("Unknown schedule ID") }
        for name in [id + ".json", id + ".sh", id + ".plist", "\(agent.stateNamespace)-" + id + ".service", "\(agent.stateNamespace)-" + id + ".timer"] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
