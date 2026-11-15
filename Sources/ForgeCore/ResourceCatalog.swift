import Foundation

/// Public metadata snapshot, collected outside the app. Contains no learner data or credentials.
public struct ResourceCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let project: String
    public let title: String
    public let fetchedAt: String?
    public let status: String
    public let categories: [ResourceCategory]
    public let items: [CatalogResource]

    public static func loadBundled() throws -> ResourceCatalog {
        let relocated = Bundle.main.resourceURL?.appendingPathComponent("ForgeMac_ForgeCore.bundle")
        let relocatedURL = relocated.flatMap { Bundle(url: $0) }?.url(forResource: "resource-catalog", withExtension: "json")
        guard let url = relocatedURL ?? Bundle.module.url(forResource: "resource-catalog", withExtension: "json") else {
            throw ResourceCatalogError.missing
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> ResourceCatalog {
        guard data.count <= 2_000_000 else { throw ResourceCatalogError.invalid }
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        let categoryIDs = Set(catalog.categories.map(\.id))
        guard catalog.schemaVersion == 1, catalog.project == "forge-macos",
              ["live", "cached", "seed", "partial"].contains(catalog.status),
              catalog.categories.count <= 20, categoryIDs.count == catalog.categories.count,
              catalog.items.count <= 500, Set(catalog.items.map(\.id)).count == catalog.items.count,
              catalog.fetchedAt == nil || catalog.collectionDate != nil,
              catalog.items.allSatisfy({ item in
                  categoryIDs.contains(item.category) && !item.fullName.isEmpty &&
                  item.url.scheme == "https" && item.url.host == "github.com" &&
                  item.url.user == nil && item.url.password == nil && item.url.port == nil &&
                  item.url.path == "/" + item.fullName &&
                  item.url.query == nil && item.url.fragment == nil &&
                  (item.stars == nil || item.stars! >= 0) &&
                  (item.fetchedAt == nil || collectionDate(from: item.fetchedAt) != nil)
              }) else { throw ResourceCatalogError.invalid }
        return catalog
    }

    /// The upstream collection time, preserved unchanged when cached locally.
    public var collectionDate: Date? { Self.collectionDate(from: fetchedAt) }

    /// An undated seed must not replace a dated snapshot. Equal dates are not older.
    public func isOlder(than other: ResourceCatalog) -> Bool {
        guard let otherDate = other.collectionDate else { return false }
        guard let date = collectionDate else { return true }
        return date < otherDate
    }

    static func collectionDate(from timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }

    public func matching(_ query: String, category: String = "") -> [CatalogResource] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { resource in
            (category.isEmpty || resource.category == category) && terms.allSatisfy { term in
                (resource.fullName + " " + resource.description + " " + resource.topics.joined(separator: " "))
                    .localizedCaseInsensitiveContains(term)
            }
        }
    }
}

public struct ResourceCategory: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
}

public struct CatalogResource: Codable, Identifiable, Sendable {
    public var id: String { category + ":" + fullName.lowercased() }
    public let fullName: String
    public let url: URL
    public let description: String
    public let topics: [String]
    public let stars: Int?
    public let license: String?
    public let category: String
    public let fetchedAt: String?
    public let stale: Bool
}

public enum ResourceCatalogError: LocalizedError {
    case missing, invalid
    public var errorDescription: String? {
        switch self {
        case .missing: "The bundled GitHub catalog is unavailable. The original library remains available."
        case .invalid: "The bundled GitHub catalog could not be validated. The original library remains available."
        }
    }
}
