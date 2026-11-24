import Foundation

public struct Configuration: Codable {
    public var commitIdentity: String = AgentDefinition.generic.commitIdentity
    public var push: Bool = false
    public var harness: String?
    public var ollamaModel: String?
    public var ollamaHost: String = "http://127.0.0.1:11434"
    public var ollamaMaxTurns: Int = 40
    public var ollamaContextLength: Int = 32768
    public var customCommand: [String]?
    public var protectedPaths: [String] = []
    public var instructions: String = ""
    public var prompt: String?
    public var maxIterations: Int = 1
    public var failureLimit: Int = 3
    public var saturationLimit: Int = AgentDefinition.generic.consecutiveNoCandidateLimit
    public var branch: String?
    public var base: String?
    public var baseline: [String]?
    public var verification: [String]?
    public var timeoutSeconds: Double = 1800
    public var maxChangedFiles: Int = 12
    public init(agent: AgentDefinition = .generic) {
        commitIdentity = agent.commitIdentity
        saturationLimit = agent.consecutiveNoCandidateLimit
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commitIdentity, forKey: .commitIdentity)
        try container.encode(push, forKey: .push)
        try container.encode(harness, forKey: .harness)
        try container.encode(ollamaModel, forKey: .ollamaModel)
        try container.encode(ollamaHost, forKey: .ollamaHost)
        try container.encode(ollamaMaxTurns, forKey: .ollamaMaxTurns)
        try container.encode(ollamaContextLength, forKey: .ollamaContextLength)
        try container.encode(customCommand, forKey: .customCommand)
        try container.encode(protectedPaths, forKey: .protectedPaths)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(maxIterations, forKey: .maxIterations)
        try container.encode(failureLimit, forKey: .failureLimit)
        try container.encode(saturationLimit, forKey: .saturationLimit)
        try container.encode(branch, forKey: .branch)
        try container.encode(base, forKey: .base)
        try container.encode(baseline, forKey: .baseline)
        try container.encode(verification, forKey: .verification)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try container.encode(maxChangedFiles, forKey: .maxChangedFiles)
    }

    public static func load(repository: Repository, agent: AgentDefinition = .generic) throws -> Configuration {
        let configBase = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
        let urls = [URL(fileURLWithPath: configBase).appendingPathComponent(agent.stateNamespace + "/config.json"), repository.root.appendingPathComponent(agent.executableName + ".json")]
        var dictionary: [String: Any] = [:]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            guard let values = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw AgentError.message("Configuration must be a JSON object: " + url.path)
            }
            dictionary.merge(values) { _, new in new }
        }
        guard
              Set(dictionary.keys).isSubset(of: ["ollamaModel", "ollamaHost", "ollamaMaxTurns", "ollamaContextLength", "commitIdentity", "branch", "base", "baseline", "verification", "timeoutSeconds", "maxChangedFiles", "harness", "customCommand", "prompt", "instructions", "maxIterations", "failureLimit", "saturationLimit", "push", "protectedPaths"]) else {
            throw AgentError.message("Repository configuration contains unknown keys or is not an object")
        }
        let defaults: [String: Any] = ["ollamaHost": Configuration(agent: agent).ollamaHost, "ollamaMaxTurns": Configuration(agent: agent).ollamaMaxTurns, "ollamaContextLength": Configuration(agent: agent).ollamaContextLength, "commitIdentity": Configuration(agent: agent).commitIdentity, "protectedPaths": [String](), "push": false, "timeoutSeconds": 1800, "maxChangedFiles": 12, "instructions": "", "maxIterations": 1, "failureLimit": 3, "saturationLimit": Configuration(agent: agent).saturationLimit]
        let merged = defaults.merging(dictionary) { _, new in new }
        let configuration = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: merged))
        try configuration.validate()
        return configuration
    }
    func commitEnvironment() throws -> [String: String] {
        if commitIdentity == "git" { return [:] }
        let value = commitIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commitIdentity.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let opening = value.lastIndex(of: "<"), value.hasSuffix(">") else {
            throw AgentError.message("Commit identity must be 'git' or 'Name <email>'")
        }
        let name = value[..<opening].trimmingCharacters(in: .whitespaces)
        let email = String(value[value.index(after: opening)..<value.index(before: value.endIndex)])
        guard !name.isEmpty, !email.isEmpty,
              !name.contains(where: { "<>".contains($0) }),
              !email.contains(where: { $0.isWhitespace || "<>".contains($0) }) else {
            throw AgentError.message("Commit identity must be 'git' or 'Name <email>'")
        }
        return ["GIT_AUTHOR_NAME": name, "GIT_AUTHOR_EMAIL": email,
                "GIT_COMMITTER_NAME": name, "GIT_COMMITTER_EMAIL": email]
    }

    func validate() throws {
        _ = try commitEnvironment()
        guard let host = URLComponents(string: ollamaHost), ["http", "https"].contains(host.scheme),
              let hostname = host.host, !hostname.isEmpty, host.query == nil, host.fragment == nil,
              host.user == nil, host.password == nil,
              ollamaMaxTurns > 0, ollamaMaxTurns <= 200,
              ollamaContextLength >= 4096, ollamaContextLength <= 1_048_576,
              ollamaModel.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else {
            throw AgentError.message("Invalid Ollama settings: use an HTTP(S) ollamaHost, a nonempty model, 1–200 turns, and 4096–1048576 context tokens")
        }
        guard maxIterations > 0, failureLimit > 0, saturationLimit > 0,
              customCommand.map({ !$0.isEmpty && !$0[0].isEmpty }) ?? true,
              timeoutSeconds.isFinite, timeoutSeconds > 0, timeoutSeconds <= 86400,
              maxChangedFiles > 0, maxChangedFiles <= 100,
              baseline?.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
              verification?.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else {
            throw AgentError.message("Invalid limits or empty verification command in repository configuration")
        }
    }
}
