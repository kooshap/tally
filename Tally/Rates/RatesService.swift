import Foundation

/// The app's only network code.
///
/// The session is ephemeral and stripped of cookies and caching, so a request
/// carries nothing that could identify the device or the portfolio. Nothing is
/// ever uploaded: these are plain GETs for public files.
actor RatesService {
    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }

    func fetch(_ endpoint: ECBEndpoint) async throws -> [FXQuote] {
        let url = endpoint.url
        guard url.host() == ECBEndpoint.host else {
            throw ECBRatesError.unexpectedHost(url.host())
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ECBRatesError.badStatus(http.statusCode)
        }

        return try ECBRatesParser.parse(data)
    }
}
