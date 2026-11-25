import Foundation
import XCTest
@testable import EmbedMissionGenerator
@testable import ProductMetadataGenerator

final class GenerationTests: XCTestCase {
    private func metadata(_ fields: [String: Any] = [:]) throws -> ProductMetadata {
        var object: [String: Any] = ["name": "Documentation Agent", "version": "0.2.0", "executableName": "doc-agent"]
        object.merge(fields) { _, new in new }
        return try ProductMetadata.parse(JSONSerialization.data(withJSONObject: object))
    }

    func testMetadataSupportsSemVerAndOptionalBuild() throws {
        for version in ["0.0.0", "12.34.56", "0.2.0-rc.1", "1.0.0+build.01", "1.0.0-alpha-beta.0+sha.123"] {
            XCTAssertEqual(try metadata(["version": version]).version, version)
        }
        XCTAssertNil(try metadata().build)
        XCTAssertNil(try metadata(["build": NSNull()]).build)
        XCTAssertEqual(try metadata(["build": "5475660"]).build, "5475660")
    }

    func testMetadataRejectsInvalidValuesTypesMissingFieldsAndRuntimeSettings() throws {
        for fields: [String: Any] in [
            ["name": " \n"], ["name": "Name\nOther"], ["name": 1], ["version": NSNull()],
            ["executableName": ""], ["executableName": "../agent"], ["executableName": "agent tool"],
            ["executableName": "é"], ["commitIdentity": []],
            ["build": ""], ["build": "\n"], ["build": 42], ["harness": "codex"], ["prompt": "prompt.md"], ["maxIterations": 2]
        ] {
            XCTAssertThrowsError(try metadata(fields), "\(fields)")
        }
        for version in ["", "0.2", "v0.2.0", "01.2.0", "1.02.0", "1.2.03", "1.0.0-01", "1.0.0-", "1.0.0+", "1.0.0\n", "1.0.0 extra"] {
            XCTAssertThrowsError(try metadata(["version": version]), version)
        }
        for data in [Data("[]".utf8), Data("null".utf8), Data("{}".utf8), Data("{invalid}".utf8)] {
            XCTAssertThrowsError(try ProductMetadata.parse(data))
        }
        for missing in ["name", "version", "executableName"] {
            var fields = ["name": "Agent", "version": "1.0.0", "executableName": "agent"]
            fields.removeValue(forKey: missing)
            XCTAssertThrowsError(try ProductMetadata.parse(JSONEncoder().encode(fields)))
        }
    }

    func testOptionalCommitIdentity() throws {
        XCTAssertNil(try metadata().commitIdentity)
        XCTAssertNil(try metadata(["commitIdentity": NSNull()]).commitIdentity)
        XCTAssertTrue(try metadata().source.contains("commitIdentity: nil"))
        for identity in ["git", "Scout <scout@localhost>", "Café 🏕️ \"Scout\" \\ name <scout@example.com>"] {
            let product = try metadata(["commitIdentity": identity])
            XCTAssertEqual(product.commitIdentity, identity)
            XCTAssertTrue(product.source.contains("let commitIdentity: String?"))
            XCTAssertTrue(product.source.contains("commitIdentity: " + ProductMetadataGenerator.swiftString(identity)))
        }
        for identity: Any in ["", " ", "Scout", "git ", "<scout@localhost>", "Scout <>",
                              "Scout <bad email>", "Scout <nested<email>>", "Scout\n <scout@localhost>",
                              "Scout <scout@localhost>\u{0000}", 42, false, []] {
            XCTAssertThrowsError(try metadata(["commitIdentity": identity]), "\(identity)")
        }
    }

    func testOptionalSourceMetadata() throws {
        XCTAssertNil(try metadata().update)
        XCTAssertNil(try metadata(["update": NSNull()]).update)
        let product = try metadata(["update": ["repository": "https://example.com/source"]])
        XCTAssertEqual(product.update?.repository, "https://example.com/source")
        XCTAssertTrue(product.source.contains("let update: Update?"))
        XCTAssertFalse(product.source.contains("import SwiftAgent"))
        XCTAssertTrue(product.source.contains(ProductMetadataGenerator.swiftString("main")))
        XCTAssertEqual(try metadata(["update": ["repository": "file:///tmp/source", "reference": "refs/tags/v1"]]).update?.reference, "refs/tags/v1")
        for update: Any in [false, [:], ["repository": "relative"], ["repository": "https://example.com/source", "reference": "-bad"], ["repository": "https://example.com/source", "branch": "main"]] {
            XCTAssertThrowsError(try metadata(["update": update]))
        }
    }

    func testMissionRejectsEmptyWhitespaceAndInvalidUTF8() {
        for data in [Data(), Data(" \n\t".utf8), Data([0xff, 0xfe])] {
            XCTAssertThrowsError(try missionSource(data))
        }
    }

    func testGeneratedSourcesAreDeterministicAndPathIndependent() throws {
        let prompt = "# Mission: café 🏕️\r\nPreserve \"quotes\", \\slashes, \\(interpolation), {prompt}, `literal` and \u{0000}.\n"
        let source = try missionSource(Data(prompt.utf8))
        XCTAssertEqual(source, try missionSource(Data(prompt.utf8)))
        XCTAssertTrue(source.contains(EmbedMissionGenerator.swiftString(prompt)))
        XCTAssertFalse(source.contains(prompt))
        let product = try metadata(["name": "Café 🏕️ \"quoted\" \\ name"])
        XCTAssertEqual(product.source, try metadata(["name": product.name]).source)
        XCTAssertTrue(product.source.contains(ProductMetadataGenerator.swiftString(product.name)))
        XCTAssertFalse(source.contains(#filePath))
        XCTAssertFalse(product.source.contains(#filePath))
    }

    func testUnchangedGenerationPreservesFileAndChangedGenerationReplacesIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writers: [(String, (String, URL) throws -> Void)] = [
            ("mission", EmbedMissionGenerator.writeGenerated),
            ("metadata", ProductMetadataGenerator.writeGenerated)
        ]
        for (name, write) in writers {
            let output = root.appendingPathComponent("\(name)/Embedded.swift")
            try write("first", output)
            let oldDate = Date(timeIntervalSince1970: 1000)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: output.path)
            try write("first", output)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date, oldDate)
            try write("second", output)
            XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "second")
            XCTAssertNotEqual(try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date, oldDate)
        }
    }
}
