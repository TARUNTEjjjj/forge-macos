import Foundation

public struct StudySession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var minutes: Int
    public var reflection: String
    public var moduleID: String?

    public init(id: UUID = UUID(), date: Date = Date(), minutes: Int,
                reflection: String, moduleID: String? = nil) {
        self.id = id
        self.date = date
        self.minutes = minutes
        self.reflection = reflection
        self.moduleID = moduleID
    }
}

public struct ProgressSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var completedModuleIDs: Set<String>
    public var notes: [String: String]
    public var dailyFocus: String
    public var sessions: [StudySession]

    public init(version: Int = 1, completedModuleIDs: Set<String> = [],
                notes: [String: String] = [:], dailyFocus: String = "",
                sessions: [StudySession] = []) {
        self.version = version
        self.completedModuleIDs = completedModuleIDs
        self.notes = notes
        self.dailyFocus = dailyFocus
        self.sessions = sessions
    }

    public var totalMinutes: Int { sessions.reduce(0) { $0 + $1.minutes } }

    public func minutes(on date: Date, calendar: Calendar = .current) -> Int {
        sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.minutes }
    }

    public func completedHours(in curriculum: Curriculum) -> Int {
        curriculum.modules.filter { completedModuleIDs.contains($0.id) }
            .reduce(0) { $0 + $1.hours }
    }
}

public enum ProgressError: LocalizedError, Equatable {
    case unsupportedVersion
    case oversizedBackup
    case invalidModule
    case invalidSession
    case textLimit
    case invalidBackup
    case damagedExistingFile

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This backup uses an unsupported format version."
        case .oversizedBackup: "The progress backup exceeds the 5 MB limit."
        case .invalidModule: "The backup refers to a lesson outside this curriculum."
        case .invalidSession: "Sessions must have unique IDs, a valid date, and 1–720 minutes."
        case .textLimit: "A note, focus, or reflection exceeds the supported text limit."
        case .invalidBackup: "This file is not a valid Forge Mac progress backup."
        case .damagedExistingFile:
            "Your saved progress could not be read. The original file has been preserved. Restore a valid backup before saving again."
        }
    }
}

/// Stores one validated snapshot using a same-volume atomic replacement.
/// A damaged existing file is never silently replaced by a fresh snapshot.
public struct ProgressFileStore: Sendable {
    public static let maximumBackupBytes = 5_000_000
    public static let maximumTextBytes = 20_000
    public static let maximumFocusBytes = 2_000
    public static let maximumSessionMinutes = 720
    public let fileURL: URL
    public let allowedModuleIDs: Set<String>

    public init(fileURL: URL, allowedModuleIDs: Set<String>) {
        self.fileURL = fileURL
        self.allowedModuleIDs = allowedModuleIDs
    }

    public func load() throws -> ProgressSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProgressSnapshot()
        }
        return try importData(readBounded(fileURL))
    }

    public func save(_ snapshot: ProgressSnapshot) throws {
        let data = try exportData(snapshot)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { _ = try load() }
            catch { throw ProgressError.damagedExistingFile }
        }
        try writeAtomically(data)
    }

    public func importData(_ data: Data) throws -> ProgressSnapshot {
        guard data.count <= Self.maximumBackupBytes else { throw ProgressError.oversizedBackup }
        let snapshot: ProgressSnapshot
        do { snapshot = try decoder.decode(ProgressSnapshot.self, from: data) }
        catch { throw ProgressError.invalidBackup }
        try validate(snapshot)
        return snapshot
    }

    public func exportData(_ snapshot: ProgressSnapshot) throws -> Data {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumBackupBytes else { throw ProgressError.oversizedBackup }
        return data
    }

    /// An explicit restore keeps the previous bytes in a uniquely named sibling
    /// file, including corrupt bytes, before atomically installing the backup.
    @discardableResult
    public func recoverFromBackup(_ data: Data) throws -> ProgressSnapshot {
        let snapshot = try importData(data)
        let normalized = try exportData(snapshot)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let preserved = fileURL.deletingLastPathComponent()
                .appendingPathComponent("progress-before-restore-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: fileURL, to: preserved)
        }
        try writeAtomically(normalized)
        return snapshot
    }

    public func validate(_ snapshot: ProgressSnapshot) throws {
        guard snapshot.version == 1 else { throw ProgressError.unsupportedVersion }
        guard snapshot.completedModuleIDs.isSubset(of: allowedModuleIDs),
              Set(snapshot.notes.keys).isSubset(of: allowedModuleIDs),
              snapshot.sessions.allSatisfy({ $0.moduleID.map(allowedModuleIDs.contains) ?? true })
        else { throw ProgressError.invalidModule }
        guard snapshot.dailyFocus.utf8.count <= Self.maximumFocusBytes,
              snapshot.notes.values.allSatisfy({ $0.utf8.count <= Self.maximumTextBytes }),
              snapshot.sessions.allSatisfy({ $0.reflection.utf8.count <= Self.maximumTextBytes })
        else { throw ProgressError.textLimit }
        guard snapshot.sessions.count <= 20_000,
              Set(snapshot.sessions.map(\.id)).count == snapshot.sessions.count,
              snapshot.sessions.allSatisfy({
                  (1...Self.maximumSessionMinutes).contains($0.minutes) && $0.date.timeIntervalSince1970.isFinite &&
                  (0...32_503_680_000).contains($0.date.timeIntervalSince1970)
              }) else { throw ProgressError.invalidSession }
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func readBounded(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= Self.maximumBackupBytes else {
            throw ProgressError.oversizedBackup
        }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBackupBytes else { throw ProgressError.oversizedBackup }
        return data
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
