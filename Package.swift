// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SwiftAgent",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftAgent", targets: ["SwiftAgent"]),
        .library(name: "SwiftAgentCLI", targets: ["SwiftAgentCLI"]),
        .executable(name: "swift-agent", targets: ["swift-agent"]),
        .plugin(name: "AgentProductPlugin", targets: ["AgentProductPlugin"])
    ],
    targets: [
        .target(name: "ProcessSupport"),
        .target(name: "SwiftAgent", dependencies: ["ProcessSupport"]),
        .target(name: "SwiftAgentCLI", dependencies: ["SwiftAgent"]),
        .executableTarget(name: "EmbedMissionGenerator"),
        .executableTarget(name: "ProductMetadataGenerator"),
        .plugin(name: "AgentProductPlugin", capability: .buildTool(), dependencies: ["ProductMetadataGenerator", "EmbedMissionGenerator"]),
        .executableTarget(name: "swift-agent", dependencies: ["SwiftAgentCLI"], exclude: ["agent.json"], plugins: ["AgentProductPlugin"]),
        .testTarget(name: "BuildToolTests", dependencies: ["EmbedMissionGenerator", "ProductMetadataGenerator"]),
        .testTarget(name: "SwiftAgentPublicTests", dependencies: ["SwiftAgent"]),
        .testTarget(name: "SwiftAgentTests", dependencies: ["SwiftAgent", "SwiftAgentCLI"])
    ]
)
