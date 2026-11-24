import Foundation
import PackagePlugin

@main
struct BuildVersion: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let root = context.package.directoryURL
        let script = root.appendingPathComponent("Scripts/build-metadata.swift")
        var inputs = [root.appendingPathComponent("VERSION"), script]
        let files = FileManager.default
        func include(_ url: URL) {
            if files.fileExists(atPath: url.path) { inputs.append(url) }
        }
        // Track Git's actual metadata, including linked worktrees and packed refs.
        // A prebuild command alone can be skipped when SwiftPM reuses its build plan.
        let dotGit = root.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        if files.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
            let gitDirectory: URL
            if isDirectory.boolValue { gitDirectory = dotGit }
            else {
                include(dotGit)
                let text = try String(contentsOf: dotGit, encoding: .utf8)
                if text.hasPrefix("gitdir: ") {
                    gitDirectory = URL(fileURLWithPath: text.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: root)
                } else { gitDirectory = dotGit }
            }
            let commonFile = gitDirectory.appendingPathComponent("commondir")
            include(commonFile)
            let commonDirectory: URL
            if let common = try? String(contentsOf: commonFile, encoding: .utf8) {
                commonDirectory = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: gitDirectory.appendingPathComponent("", isDirectory: true))
            } else { commonDirectory = gitDirectory }
            // Directory inputs remain valid when Git packs/deletes loose refs or
            // switches branches; individual ref-file inputs can become stale.
            include(gitDirectory)
            if commonDirectory.standardizedFileURL != gitDirectory.standardizedFileURL {
                include(commonDirectory)
            }
        }
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("Generated/BuildVersion.swift")
        return [.buildCommand(
            displayName: "Embed SwiftAgent version and build",
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["swift", script.path, root.path, context.pluginWorkDirectoryURL.path],
            inputFiles: inputs, outputFiles: [output])]
    }
}
