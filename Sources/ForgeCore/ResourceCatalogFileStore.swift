import Foundation
import Darwin

/// A disposable cache of validated public metadata, independent of learner progress.
public struct ResourceCatalogFileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    /// Absence is normal. Damaged, oversized, and nonregular files are rejected.
    public func load() throws -> ResourceCatalog? {
        guard fileURL.isFileURL else { throw ResourceCatalogFileStoreError.unsafeLocation }
        let descriptor = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard information.st_mode & S_IFMT == S_IFREG else {
            throw ResourceCatalogFileStoreError.unsafeLocation
        }
        let limit = ResourceCatalog.maximumDownloadBytes
        guard information.st_size >= 0, information.st_size <= limit else {
            throw ResourceCatalogFileStoreError.invalidContents
        }
        var data = Data()
        while data.count <= limit {
            let chunk = try handle.read(upToCount: limit + 1 - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
            guard data.count <= limit else { throw ResourceCatalogFileStoreError.invalidContents }
        }
        do { return try ResourceCatalog.decode(data) }
        catch { throw ResourceCatalogFileStoreError.invalidContents }
    }

    /// Validate before touching disk; replace atomically. Older snapshots leave the
    /// saved bytes unchanged. A new valid download can repair a damaged cache.
    @discardableResult
    public func save(_ catalog: ResourceCatalog) throws -> Bool {
        guard fileURL.isFileURL else { throw ResourceCatalogFileStoreError.unsafeLocation }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(catalog)
        _ = try ResourceCatalog.decode(data)
        var previous: ResourceCatalog?
        do { previous = try load() }
        catch ResourceCatalogFileStoreError.invalidContents { previous = nil }
        if let previous, catalog.isOlder(than: previous) { return false }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return true
    }
}

public enum ResourceCatalogFileStoreError: LocalizedError {
    case invalidContents, unsafeLocation

    public var errorDescription: String? {
        switch self {
        case .invalidContents: "The saved resource catalog is damaged or exceeds the size limit."
        case .unsafeLocation: "The saved resource catalog must be a regular local file."
        }
    }
}
