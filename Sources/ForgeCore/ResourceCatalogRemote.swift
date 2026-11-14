import Foundation

private final class CatalogRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Catalog ownership is fixed. Never forward a request to another destination.
        completionHandler(nil)
    }
}

extension ResourceCatalog {
    public static let latestURL = URL(string: "https://raw.githubusercontent.com/TARUNTEjjjj/forge-macos/main/resources/catalog.json")!
    public static let maximumDownloadBytes = 2_000_000

    /// Read public metadata only. No account cookies, credentials, progress, or disk cache.
    public static func loadLatest(configuration: URLSessionConfiguration = .ephemeral) async throws -> ResourceCatalog {
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: CatalogRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json, text/plain", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200, response.url == latestURL else {
            throw ResourceCatalogRemoteError.invalidResponse
        }
        guard response.expectedContentLength <= Int64(maximumDownloadBytes) else {
            throw ResourceCatalogRemoteError.tooLarge
        }
        var data = Data()
        data.reserveCapacity(Int(max(0, response.expectedContentLength)))
        for try await byte in bytes {
            guard data.count < maximumDownloadBytes else { throw ResourceCatalogRemoteError.tooLarge }
            data.append(byte)
        }
        return try decode(data)
    }

    public var hasStaleMetadata: Bool { items.contains { $0.isStale() } }
}

extension CatalogResource {
    public func isStale(at now: Date = Date()) -> Bool {
        if stale { return true }
        guard let fetchedAt else { return stars != nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var verified = formatter.date(from: fetchedAt)
        if verified == nil {
            formatter.formatOptions = [.withInternetDateTime]
            verified = formatter.date(from: fetchedAt)
        }
        guard let verified else { return true }
        return now.timeIntervalSince(verified) > 24 * 60 * 60
    }
}

public enum ResourceCatalogRemoteError: LocalizedError {
    case invalidResponse, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The public GitHub catalog did not return the expected response."
        case .tooLarge: "The public GitHub catalog exceeded the download limit."
        }
    }
}
