// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftAgent",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftAgent", targets: ["SwiftAgent"]),
        .library(name: "SwiftAgentCLI", targets: ["SwiftAgentCLI"]),
        .executable(name: "swift-agent", targets: ["swift-agent"])
    ],
    targets: [
        .target(name: "ProcessSupport"),
        .target(name: "SwiftAgent", dependencies: ["ProcessSupport"]),
        .target(name: "SwiftAgentCLI", dependencies: ["SwiftAgent"]),
        .plugin(name: "BuildVersion", capability: .buildTool()),
        .executableTarget(name: "swift-agent", dependencies: ["SwiftAgentCLI"], plugins: ["BuildVersion"]),
        .testTarget(name: "SwiftAgentPublicTests", dependencies: ["SwiftAgent"]),
        .testTarget(name: "SwiftAgentTests", dependencies: ["SwiftAgent", "SwiftAgentCLI"])
    ]
)
