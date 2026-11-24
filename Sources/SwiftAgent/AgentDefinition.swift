/// Identity and defaults for an iterative repository agent. No mission is assumed.
public struct AgentDefinition: Sendable {
    public let name: String
    public let executableName: String
    public let mission: String?
    public let commitIdentity: String
    public let branchNamespace: String
    public let stateNamespace: String
    public let consecutiveNoCandidateLimit: Int

    public init(name: String, executableName: String, mission: String? = nil,
                commitIdentity: String? = nil, branchNamespace: String? = nil,
                stateNamespace: String? = nil, consecutiveNoCandidateLimit: Int = 2) {
        precondition(!name.isEmpty)
        for component in [executableName, branchNamespace ?? executableName, stateNamespace ?? executableName] {
            precondition(!component.isEmpty && component != "." && component != ".." &&
                         component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        }
        precondition(consecutiveNoCandidateLimit > 0)
        self.name = name
        self.executableName = executableName
        self.mission = mission
        self.commitIdentity = commitIdentity ?? "\(name) <\(executableName)@localhost>"
        self.branchNamespace = branchNamespace ?? executableName
        self.stateNamespace = stateNamespace ?? executableName
        self.consecutiveNoCandidateLimit = consecutiveNoCandidateLimit
    }

    public static let generic = AgentDefinition(name: "Swift Agent", executableName: "swift-agent")
}
