import XCTest
@testable import Tally

/// §8: stands in for a network monitor. Every request the app makes passes
/// through this protocol, which records the host and fails the test if anything
/// but the ECB is contacted, or if a request carries a body or a cookie.
final class RecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var lock = NSLock()
    nonisolated(unsafe) private static var _requests: [URLRequest] = []
    nonisolated(unsafe) private static var _stub: Data = Data()

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func reset(stub: Data) {
        lock.lock(); defer { lock.unlock() }
        _requests = []
        _stub = stub
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock()
        _requests.append(request)
        lock.unlock()
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let data = Self._stub
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/xml"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RatesServiceTests: XCTestCase {
    private func makeService(stub: Data) -> RatesService {
        RecordingURLProtocol.reset(stub: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        return RatesService(session: URLSession(configuration: configuration))
    }

    private func dailyFixture() throws -> Data {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(bundle.url(forResource: "eurofxref-daily", withExtension: "xml"))
        return try Data(contentsOf: url)
    }

    func testEveryEndpointPointsAtTheECBAndNowhereElse() {
        for endpoint in ECBEndpoint.allCases {
            XCTAssertEqual(endpoint.url.host(), ECBEndpoint.host, "\(endpoint) escaped the ECB host")
            XCTAssertEqual(endpoint.url.scheme, "https")
        }
    }

    func testFetchingContactsOnlyTheECB() async throws {
        let service = makeService(stub: try dailyFixture())

        _ = try await service.fetch(.daily)

        let hosts = Set(RecordingURLProtocol.requests.compactMap { $0.url?.host() })
        XCTAssertEqual(hosts, [ECBEndpoint.host])
    }

    /// Nothing about the user goes out: no body, no cookies, no custom headers
    /// that could act as an identifier.
    func testRequestsCarryNoUserData() async throws {
        let service = makeService(stub: try dailyFixture())

        _ = try await service.fetch(.daily)

        let request = try XCTUnwrap(RecordingURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testFetchReturnsParsedQuotes() async throws {
        let service = makeService(stub: try dailyFixture())

        let quotes = try await service.fetch(.daily)

        XCTAssertEqual(quotes.count, 29)
        XCTAssertTrue(quotes.allSatisfy { $0.unitsPerEUR > 0 })
    }

    func testGarbageResponseThrowsInsteadOfCachingNonsense() async throws {
        let service = makeService(stub: Data("not xml at all".utf8))

        do {
            _ = try await service.fetch(.daily)
            XCTFail("expected a parse failure")
        } catch {
            XCTAssertTrue(error is ECBRatesError)
        }
    }
}
