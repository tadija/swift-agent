import XCTest
@testable import SwiftAgent

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OllamaHTTPTests: XCTestCase {
    override func tearDown() {
        OllamaURLProtocol.handler = nil
        Cancellation.requested = 0
        super.tearDown()
    }

    func testLANEndpointAndJSONRequest() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaURLProtocol.self]
        OllamaURLProtocol.handler = { request, client, stub in
            XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.50:11434/api/show")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client.urlProtocol(stub, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(stub, didLoad: Data("{\"capabilities\":[\"tools\"]}".utf8))
            client.urlProtocolDidFinishLoading(stub)
        }
        let response = try OllamaHTTP.post(host: "http://192.168.1.50:11434", endpoint: "api/show", body: ["model": "fixture"], timeout: 2, configuration: config)
        XCTAssertEqual(response["capabilities"] as? [String], ["tools"])
    }

    func testHTTPErrorsAndInvalidJSONAreReported() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaURLProtocol.self]
        for (status, body) in [(404, "{\"error\":\"model not found\"}"), (200, "Ollama is running"), (200, "[]")] {
            OllamaURLProtocol.handler = { request, client, stub in
                client.urlProtocol(stub, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(stub, didLoad: Data(body.utf8))
                client.urlProtocolDidFinishLoading(stub)
            }
            XCTAssertThrowsError(try OllamaHTTP.post(host: "http://localhost:11434", endpoint: "api/chat", body: [:], timeout: 2, configuration: config))
        }
    }

    func testStalledRequestsRespectTimeoutAndCancellation() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaURLProtocol.self]
        OllamaURLProtocol.handler = { _, _, _ in }
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try OllamaHTTP.post(host: "http://localhost:11434", endpoint: "api/chat", body: [:], timeout: 0.1, configuration: config))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        Cancellation.requested = 1
        XCTAssertThrowsError(try OllamaHTTP.post(host: "http://localhost:11434", endpoint: "api/chat", body: [:], timeout: 10, configuration: config))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }
}

private final class OllamaURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest, URLProtocolClient, OllamaURLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let client { Self.handler?(request, client, self) }
    }
    override func stopLoading() {}
}
