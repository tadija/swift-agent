import SwiftAgent
import SwiftAgentCLI
#if os(Linux)
import Glibc
#else
import Darwin
#endif

exit(AgentCLI.run(agent: .generic, version: "Swift Agent \(BuildVersion.version) (\(BuildVersion.build))"))
