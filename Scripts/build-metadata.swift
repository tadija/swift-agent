import Foundation

// Run by the SwiftPM build-tool plugin so ref-only changes also refresh metadata.
// Usage: swift build-metadata.swift PACKAGE_DIRECTORY OUTPUT_DIRECTORY
func generate() throws {
    guard CommandLine.arguments.count == 3 else {
        throw MetadataError.message("Expected package and output directories")
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        .standardizedFileURL.resolvingSymlinksInPath()
    let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        .appendingPathComponent("Generated", isDirectory: true)
    let version = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let number = "(0|[1-9][0-9]*)"
    let identifier = "(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    let pattern = "^\(number)\\.\(number)\\.\(number)(-\(identifier)(\\.\(identifier))*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$"
    guard !version.isEmpty, version.range(of: pattern, options: .regularExpression) == version.startIndex..<version.endIndex else {
        throw MetadataError.message("VERSION must contain a Semantic Version, such as 0.2.1")
    }

    func git(_ arguments: [String]) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var build = "unknown"
    if let repository = try git(["rev-parse", "--show-toplevel"]),
       URL(fileURLWithPath: repository).resolvingSymlinksInPath() == root,
       let revision = try git(["rev-parse", "--verify", "HEAD^{commit}"]),
       [40, 64].contains(revision.count),
       revision.allSatisfy({ $0.isASCII && $0.isHexDigit }) {
        build = String(revision.prefix(7)).lowercased()
    }
    let source = """
    // Generated from VERSION and Git HEAD. Do not edit.
    enum BuildVersion {
        static let version = "\(version)"
        static let build = "\(build)"
        static let display = "Swift Agent \\(version) (\\(build))"
    }

    """
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let destination = output.appendingPathComponent("BuildVersion.swift")
    if (try? String(contentsOf: destination, encoding: .utf8)) != source {
        try source.write(to: destination, atomically: true, encoding: .utf8)
    }
}

enum MetadataError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let message): message } }
}

do {
    try generate()
} catch {
    FileHandle.standardError.write(Data("Build metadata: \(error)\n".utf8))
    exit(1)
}
