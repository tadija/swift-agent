import SwiftAgent
import SwiftAgentCLI
#if os(Linux)
import Glibc
#else
import Darwin
#endif

let product = EmbeddedProduct.metadata
let agent = AgentDefinition(name: product.name, executableName: product.executableName,
                            commitIdentity: product.commitIdentity)
do {
    let update = try product.update.map {
        try SourceUpdateConfiguration(repository: $0.repository, reference: $0.reference)
    }
    exit(AgentCLI.run(agent: agent, version: product.displayVersion, sourceUpdate: update))
} catch {
    print(error)
    exit(1)
}
