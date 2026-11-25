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

/// Build-time product data. Independent of SwiftAgent and the input filename.
struct ProductMetadata: Decodable, Equatable {
    let name: String
    let version: String
    let build: String?
    let executableName: String
    let commitIdentity: String?
    let update: Update?

    struct Update: Decodable, Equatable {
        let repository: String
        let reference: String?
    }

    static func parse(_ data: Data) throws -> ProductMetadata {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GenerationError("Product metadata must be a JSON object")
        }
        let unknown = Set(object.keys).subtracting(["name", "version", "build", "executableName", "commitIdentity", "update"])
        guard unknown.isEmpty else {
            throw GenerationError("Unknown product metadata keys: \(unknown.sorted().joined(separator: ", "))")
        }
        let metadata = try JSONDecoder().decode(Self.self, from: data)
        guard !metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !metadata.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw GenerationError("name must be nonempty and contain no control characters")
        }
        guard !metadata.executableName.isEmpty,
              metadata.executableName.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw GenerationError("executableName must contain only ASCII letters, digits, hyphens or underscores")
        }
        // Preserve the existing SemVer convention, including prerelease/build identifiers.
        let number = "(0|[1-9][0-9]*)"
        let identifier = "(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
        let pattern = "^\(number)\\.\(number)\\.\(number)(-\(identifier)(\\.\(identifier))*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$"
        guard metadata.version.range(of: pattern, options: .regularExpression) == metadata.version.startIndex..<metadata.version.endIndex else {
            throw GenerationError("version must be a Semantic Version, such as 0.2.0")
        }
        if let build = metadata.build {
            guard !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !build.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw GenerationError("build must be nonempty and contain no control characters")
            }
        }
        if let identity = metadata.commitIdentity, identity != "git" {
            let value = identity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identity.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  let opening = value.lastIndex(of: "<"), value.hasSuffix(">") else {
                throw GenerationError("commitIdentity must be 'git' or 'Name <email>'")
            }
            let name = value[..<opening].trimmingCharacters(in: .whitespaces)
            let email = value[value.index(after: opening)..<value.index(before: value.endIndex)]
            guard !name.isEmpty, !email.isEmpty,
                  !name.contains(where: { "<>".contains($0) }),
                  !email.contains(where: { $0.isWhitespace || "<>".contains($0) }) else {
                throw GenerationError("commitIdentity must be 'git' or 'Name <email>'")
            }
        }
        if let update = metadata.update {
            guard let fields = object["update"] as? [String: Any],
                  Set(fields.keys).subtracting(["repository", "reference"]).isEmpty else {
                throw GenerationError("update accepts only repository and reference")
            }
            guard let url = URL(string: update.repository),
                  ["https", "ssh", "file"].contains(url.scheme ?? ""),
                  (url.isFileURL ? url.path.hasPrefix("/") : url.host?.isEmpty == false),
                  !update.repository.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw GenerationError("update.repository must be an absolute https, ssh or file URL")
            }
            if let ref = update.reference {
                guard !ref.isEmpty, !ref.hasPrefix("-"),
                      !ref.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
                    throw GenerationError("update.reference must be nonempty without whitespace or a leading hyphen")
                }
            }
        }
        return metadata
    }

    var source: String {
        """
        // Generated product metadata. Do not edit.
        enum EmbeddedProduct {
            struct Update: Sendable {
                let repository: String
                let reference: String
            }
            struct Metadata: Sendable {
                let name: String
                let version: String
                let build: String?
                let executableName: String
                let commitIdentity: String?
                let update: Update?
                var displayVersion: String {
                    let display = "\\(name) \\(version)"
                    return build.map { "\\(display) (\\($0))" } ?? display
                }
            }
            static let metadata = Metadata(
                name: \(swiftString(name)),
                version: \(swiftString(version)),
                build: \(build.map(swiftString) ?? "nil"),
                executableName: \(swiftString(executableName)),
                commitIdentity: \(commitIdentity.map(swiftString) ?? "nil"),
                update: \(update.map { "Update(repository: \(swiftString($0.repository)), reference: \(swiftString($0.reference ?? "main")))" } ?? "nil")
            )
        }

        """
    }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw GenerationError("Usage: ProductMetadataGenerator INPUT_JSON OUTPUT_SWIFT")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let metadata = try ProductMetadata.parse(data)
    try writeGenerated(metadata.source, to: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    FileHandle.standardError.write(Data("ProductMetadataGenerator: \(error)\n".utf8))
    exit(1)
}
