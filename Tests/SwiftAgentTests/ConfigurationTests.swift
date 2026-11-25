import XCTest
@testable import SwiftAgent

final class ConfigurationTests: XCTestCase {
    func testDefaultEncodingIncludesAutomaticSettingsAsNull() throws {
        let data = try JSONEncoder().encode(Configuration(agent: .testAgent))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object.count, 20)
        for key in ["prompt", "ollamaModel", "harness", "customCommand", "branch", "base", "baseline", "verification"] {
            XCTAssertTrue(object[key] is NSNull, "Expected null default for \(key)")
        }
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        try decoded.validate()
        XCTAssertEqual(decoded.maxIterations, 1)
        XCTAssertEqual(decoded.failureLimit, 3)
        XCTAssertEqual(decoded.saturationLimit, 2)
        XCTAssertFalse(decoded.push)
        XCTAssertEqual(decoded.instructions, "")
        XCTAssertEqual(decoded.protectedPaths, [])
        XCTAssertEqual(decoded.timeoutSeconds, 1800)
        XCTAssertEqual(decoded.maxChangedFiles, 12)
        XCTAssertEqual(decoded.ollamaHost, "http://127.0.0.1:11434")
        XCTAssertEqual(decoded.ollamaMaxTurns, 40)
        XCTAssertEqual(decoded.ollamaContextLength, 32768)
        XCTAssertEqual(decoded.commitIdentity, Configuration(agent: .testAgent).commitIdentity)
    }

    func testOllamaSettingsAcceptLANHostAndRejectInvalidValues() throws {
        var configuration = Configuration(agent: .testAgent)
        configuration.ollamaHost = "http://192.168.1.50:11434"
        configuration.ollamaModel = "local-model:latest"
        XCTAssertNoThrow(try configuration.validate())
        for host in ["localhost:11434", "file:///tmp/ollama", "http://", "http://user:secret@localhost:11434", "http://localhost:11434?model=x"] {
            configuration.ollamaHost = host
            XCTAssertThrowsError(try configuration.validate(), host)
        }
        configuration.ollamaHost = Configuration(agent: .testAgent).ollamaHost
        configuration.ollamaMaxTurns = 0
        XCTAssertThrowsError(try configuration.validate())
        configuration.ollamaMaxTurns = 40
        configuration.ollamaContextLength = 0
        XCTAssertThrowsError(try configuration.validate())
    }

    func testTimeoutValidationRequiresFinitePositiveValueWithinOneDay() throws {
        var configuration = Configuration(agent: .testAgent)
        for timeout in [Double.nan, .infinity, -.infinity, -1, 0, 86400.0.nextUp] {
            configuration.timeoutSeconds = timeout
            XCTAssertThrowsError(try configuration.validate(), "Accepted timeout: \(timeout)")
        }
        for timeout in [0.001, 1800, 86400] {
            configuration.timeoutSeconds = timeout
            XCTAssertNoThrow(try configuration.validate(), "Rejected timeout: \(timeout)")
        }
    }
}
