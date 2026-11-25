import Foundation
import PackagePlugin

@main
struct AgentProductPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let metadata = target.directoryURL.appendingPathComponent("agent.json")
        guard FileManager.default.fileExists(atPath: metadata.path) else {
            Diagnostics.error("AgentProductPlugin requires agent.json in target \(target.name): \(metadata.path)")
            return []
        }
        let productOutput = context.pluginWorkDirectoryURL.appendingPathComponent("EmbeddedProduct.swift")
        var commands: [Command] = [.buildCommand(
            displayName: "AgentProductPlugin: metadata for \(target.name)",
            executable: try context.tool(named: "ProductMetadataGenerator").url,
            arguments: [metadata.path, productOutput.path],
            inputFiles: [metadata], outputFiles: [productOutput])]

        let mission = target.directoryURL.appendingPathComponent("prompt.md")
        if FileManager.default.fileExists(atPath: mission.path) {
            let missionOutput = context.pluginWorkDirectoryURL.appendingPathComponent("EmbeddedMission.swift")
            commands.append(.buildCommand(
                displayName: "AgentProductPlugin: mission for \(target.name)",
                executable: try context.tool(named: "EmbedMissionGenerator").url,
                arguments: [mission.path, missionOutput.path],
                inputFiles: [mission], outputFiles: [missionOutput]))
        }
        return commands
    }
}
