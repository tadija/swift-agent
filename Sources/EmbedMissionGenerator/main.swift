import Foundation

struct GenerationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// Byte literals preserve UTF-8 independently of Swift string escaping/interpolation.
func swiftString(_ string: String) -> String {
    "String(decoding: [\(string.utf8.map(String.init).joined(separator: ","))] as [UInt8], as: UTF8.self)"
}

func writeGenerated(_ source: String, to output: URL) throws {
    let data = Data(source.utf8)
    if (try? Data(contentsOf: output)) == data { return }
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: output, options: .atomic)
}

func missionSource(_ data: Data) throws -> String {
    guard let prompt = String(data: data, encoding: .utf8),
          !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw GenerationError("Mission must be nonempty UTF-8 Markdown")
    }
    return """
    // Generated mission. Do not edit.
    enum EmbeddedMission {
        static let prompt = \(swiftString(prompt))
    }

    """
}

// Explicit paths keep the executable reusable independently of the plugin convention.
do {
    guard CommandLine.arguments.count == 3 else {
        throw GenerationError("Usage: EmbedMissionGenerator INPUT_MARKDOWN OUTPUT_SWIFT")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    try writeGenerated(missionSource(data), to: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    FileHandle.standardError.write(Data("EmbedMissionGenerator: \(error)\n".utf8))
    exit(1)
}
