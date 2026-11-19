import Foundation
import Darwin

public struct StudySession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var minutes: Int
    public var reflection: String
    public var moduleID: String?
    /// Fields this build does not model, such as ones a newer Forge version added.
    /// They are written back with the same values, so saving here never erases them.
    fileprivate var otherFields: [String: JSONValue] = [:]

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
    /// Top-level fields this build does not model; see `StudySession.otherFields`.
    fileprivate var otherFields: [String: JSONValue] = [:]

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

    /// Searches reflections and lesson titles while keeping date bounds half-open.
    /// Filtering never changes the stored history or the totals shown elsewhere.
    /// For repeated searches of one history, build a `SessionSearchIndex` once instead.
    public func filteredSessions(query: String = "", moduleID: String? = nil,
                                 since: Date? = nil, before: Date? = nil,
                                 moduleTitles: [String: String] = [:]) -> [StudySession] {
        SessionSearchIndex(sessions: sessions, moduleTitles: moduleTitles)
            .matches(SessionSearch(query: query, moduleID: moduleID, since: since, before: before))?.sessions ?? []
    }

    public func minutes(on date: Date, calendar: Calendar = .current) -> Int {
        sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.minutes }
    }

    /// Totals in the requested order, including repeated or empty days. A single
    /// pass over history keeps multi-day charts independent of the number of bars.
    /// Calendar day boundaries also handle time zones and daylight-saving changes.
    public func minutes(on dates: [Date], calendar: Calendar = .current) -> [Int] {
        let days = dates.map { calendar.startOfDay(for: $0) }
        guard !days.isEmpty else { return [] }
        var totals = Dictionary(uniqueKeysWithValues: Set(days).map { ($0, 0) })
        for session in sessions {
            let day = calendar.startOfDay(for: session.date)
            if let total = totals[day] { totals[day] = total + session.minutes }
        }
        return days.map { totals[$0, default: 0] }
    }

    public func completedHours(in curriculum: Curriculum) -> Int {
        curriculum.modules.filter { completedModuleIDs.contains($0.id) }
            .reduce(0) { $0 + $1.hours }
    }

    /// Reviewed lessons that `curriculum` contains. Progress can also name lessons
    /// from another curriculum version; those are kept but not counted.
    public func completedModuleCount(in curriculum: Curriculum) -> Int {
        curriculum.modules.filter { completedModuleIDs.contains($0.id) }.count
    }
}

extension StudySession {
    private enum CodingKeys: String, CodingKey { case id, date, minutes, reflection, moduleID }

    public init(from decoder: Decoder) throws {
        let fields = try ObjectFields<CodingKeys>(decoder)
        id = try fields.decode(UUID.self, .id)
        date = try fields.decode(Date.self, .date)
        minutes = try fields.decode(Int.self, .minutes)
        reflection = try fields.decode(String.self, .reflection)
        moduleID = try fields.decodeIfPresent(String.self, .moduleID)
        otherFields = fields.otherFields()
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(id, forKey: .id)
        try fields.encode(date, forKey: .date)
        try fields.encode(minutes, forKey: .minutes)
        try fields.encode(reflection, forKey: .reflection)
        try fields.encodeIfPresent(moduleID, forKey: .moduleID)
        try encoder.encode(otherFields: otherFields)
    }
}

extension ProgressSnapshot {
    private enum CodingKeys: String, CodingKey { case version, completedModuleIDs, notes, dailyFocus, sessions }

    public init(from decoder: Decoder) throws {
        let fields = try ObjectFields<CodingKeys>(decoder)
        version = try fields.decode(Int.self, .version)
        completedModuleIDs = try fields.decode(Set<String>.self, .completedModuleIDs)
        notes = try fields.decode([String: String].self, .notes)
        dailyFocus = try fields.decode(String.self, .dailyFocus)
        sessions = try fields.decode([StudySession].self, .sessions)
        otherFields = fields.otherFields()
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(version, forKey: .version)
        try fields.encode(completedModuleIDs, forKey: .completedModuleIDs)
        try fields.encode(notes, forKey: .notes)
        try fields.encode(dailyFocus, forKey: .dailyFocus)
        try fields.encode(sessions, forKey: .sessions)
        try encoder.encode(otherFields: otherFields)
    }
}

/// Matches any JSON object key, so decoding can find fields this build does not model.
private struct FieldKey: CodingKey {
    let stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}

/// A JSON value kept for a field this build does not model.
private enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), decimal(Decimal), number(Double), string(String)
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) {
            // Decimal keeps 38 digits, so an integer past Int64 or a long fraction is written
            // back as read. Double, with 17 digits, holds what is beyond Decimal's range.
            if let decimal = try? value.decode(Decimal.self), Double(decimal.description) == number { self = .decimal(decimal) }
            else { self = .number(number) }
        }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let bool): try value.encode(bool)
        case .decimal(let decimal): try value.encode(decimal)
        case .number(let number): try value.encode(number)
        case .string(let string): try value.encode(string)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        }
    }
}

/// Reads one JSON object in a single pass: the modeled fields by key, and every
/// other field as a `JSONValue`.
private struct ObjectFields<Modeled: CodingKey> {
    private let fields: KeyedDecodingContainer<FieldKey>

    init(_ decoder: Decoder) throws { fields = try decoder.container(keyedBy: FieldKey.self) }

    func decode<T: Decodable>(_ type: T.Type, _ key: Modeled) throws -> T {
        try fields.decode(type, forKey: FieldKey(stringValue: key.stringValue))
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, _ key: Modeled) throws -> T? {
        try fields.decodeIfPresent(type, forKey: FieldKey(stringValue: key.stringValue))
    }

    /// The fields `Modeled` doesn't name. One that can't be kept, such as the number 1e999,
    /// is left out, as builds before this one left out every such field, so it never stops
    /// progress or a backup from loading.
    func otherFields() -> [String: JSONValue] {
        var other: [String: JSONValue] = [:]
        for key in fields.allKeys where Modeled(stringValue: key.stringValue) == nil {
            other[key.stringValue] = try? fields.decode(JSONValue.self, forKey: key)
        }
        return other
    }
}

extension Encoder {
    fileprivate func encode(otherFields: [String: JSONValue]) throws {
        guard !otherFields.isEmpty else { return }
        var fields = container(keyedBy: FieldKey.self)
        for (name, value) in otherFields { try fields.encode(value, forKey: FieldKey(stringValue: name)) }
    }
}

public enum ProgressError: LocalizedError, Equatable {
    case unsupportedVersion
    case oversizedBackup
    /// No longer thrown: progress that names lessons outside the bundled curriculum
    /// is kept (see `ProgressFileStore.allowedModuleIDs`). Kept for source compatibility.
    case invalidModule
    case invalidSession
    case textLimit
    case invalidBackup
    case damagedExistingFile
    /// Another Forge window or app saved progress after this store last loaded or saved it.
    case changedElsewhere

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This backup uses an unsupported format version."
        case .oversizedBackup: "Forge progress files and backups are limited to \(ProgressFileStore.maximumBackupBytes / 1_000_000) MB."
        case .invalidModule: "The backup refers to a lesson outside this curriculum."
        case .invalidSession: "A journal can hold up to 20,000 sessions, each with a unique ID, a valid date, and 1–720 minutes."
        case .textLimit: "A note, focus, or reflection exceeds the supported text limit."
        case .invalidBackup: "This file is not a valid Forge Mac progress backup."
        case .damagedExistingFile:
            "Your saved progress could not be read. The original file has been preserved. Restore a valid backup before saving again."
        case .changedElsewhere:
            "Your progress was saved elsewhere, such as in another Forge window, after this window loaded it. That newer progress was kept."
        }
    }
}

/// Stores one validated snapshot using a same-volume atomic replacement.
/// A damaged existing file is never silently replaced by a fresh snapshot, and
/// progress saved elsewhere, such as by another Forge window, is never replaced by
/// older progress.
public struct ProgressFileStore: Sendable {
    /// The largest progress file or backup: room for the 20,000-session limit with
    /// reflections averaging about 2 KB, plus every lesson note at its own limit.
    public static let maximumBackupBytes = 50_000_000
    public static let maximumTextBytes = 20_000
    public static let maximumFocusBytes = 2_000
    public static let maximumSessionMinutes = 720
    public let fileURL: URL
    /// The bundled curriculum's lesson IDs. Saved progress and backups may also name
    /// lessons that another curriculum version had. Validation keeps those instead of
    /// rejecting them, so renaming or retiring a lesson never locks a learner out.
    public let allowedModuleIDs: Set<String>
    private let known = KnownContents()

    public init(fileURL: URL, allowedModuleIDs: Set<String>) {
        self.fileURL = fileURL
        self.allowedModuleIDs = allowedModuleIDs
    }

    public func load() throws -> ProgressSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProgressSnapshot()
        }
        let data = try readBounded(fileURL)
        let snapshot = try importData(data)
        known.update(data)
        return snapshot
    }

    /// Saves `snapshot`, which must build on the progress this store last loaded or
    /// saved. When another Forge window or app has saved since, the file is left as
    /// it is and this throws `changedElsewhere`; `save(_:applying:)` merges instead.
    public func save(_ snapshot: ProgressSnapshot) throws {
        let data = try exportData(snapshot)
        try withWriteLock {
            guard try newerSavedProgress() == nil else { throw ProgressError.changedElsewhere }
            try writeAtomically(data)
            known.update(data)
        }
    }

    /// Applies `change` to the newest saved progress, saves the result and returns it.
    /// `current` is the progress this store last loaded or saved. When another Forge
    /// window or app has saved valid progress since, `change` is applied to that
    /// instead, so a window showing older progress never erases newer work.
    /// The change runs inside the write transaction; it must not call save or restore.
    public func save(_ current: ProgressSnapshot,
                     applying change: (inout ProgressSnapshot) -> Void) throws -> ProgressSnapshot {
        try withWriteLock {
            var snapshot = try newerSavedProgress() ?? current
            change(&snapshot)
            let data = try exportData(snapshot)
            try writeAtomically(data)
            known.update(data)
            return snapshot
        }
    }

    /// Valid progress on disk that this store did not load or write itself, such as
    /// progress that another Forge window or app saved, or nil when there is none.
    /// A file that can't be read or validated throws `damagedExistingFile`.
    public func newerSavedProgress() throws -> ProgressSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        // Bytes this store loaded or wrote have passed validation already. Anything
        // else, such as a damaged file or one saved elsewhere, is checked in full.
        do {
            let existing = try readBounded(fileURL)
            return known.matches(existing) ? nil : try importData(existing)
        } catch { throw ProgressError.damagedExistingFile }
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

    /// An explicit restore keeps the previous bytes in a dated sibling file,
    /// including corrupt bytes, before atomically installing the backup.
    @discardableResult
    public func recoverFromBackup(_ data: Data) throws -> ProgressSnapshot {
        try restoreBackup(data).snapshot
    }

    /// Restores like `recoverFromBackup`, and also returns the recovery copy of the
    /// previous file, or nil when there was no progress file to keep.
    public func restoreBackup(_ data: Data) throws -> (snapshot: ProgressSnapshot, recoveryCopy: URL?) {
        let snapshot = try importData(data)
        let normalized = try exportData(snapshot)
        return try withWriteLock {
            let copy = try keepRecoveryCopy()
            try writeAtomically(normalized)
            known.update(normalized)
            return (snapshot, copy)
        }
    }

    /// The recovery copies that restores have kept beside the progress file, by name.
    public func recoveryCopies() -> [URL] {
        let folder = fileURL.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(Self.recoveryCopyPrefix) && $0.hasSuffix(".json") }.sorted()
            .map { folder.appendingPathComponent($0) }
    }

    public func validate(_ snapshot: ProgressSnapshot) throws {
        guard snapshot.version == 1 else { throw ProgressError.unsupportedVersion }
        // Lesson IDs are deliberately not checked against `allowedModuleIDs`.
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

    /// Lock a stable sibling, not the progress inode replaced by an atomic write.
    /// Keep the lock file in place: unlinking it could give two writers different
    /// inodes to lock. Closing releases the lock even when the operation throws.
    private func withWriteLock<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let lockURL = fileURL.appendingPathExtension("lock")
        var descriptor: Int32
        repeat {
            descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, mode_t(0o600))
        } while descriptor < 0 && errno == EINTR
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard information.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.EINVAL) }
        var result: Int32
        repeat { result = flock(descriptor, LOCK_EX) } while result < 0 && errno == EINTR
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return try operation()
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static let recoveryCopyPrefix = "progress-before-restore-"

    /// Copies the current file, if any, to a name dated in the learner's time zone,
    /// such as progress-before-restore-2026-11-09-103015.json.
    private func keepRecoveryCopy() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = Self.recoveryCopyPrefix + formatter.string(from: Date())
        let folder = fileURL.deletingLastPathComponent()
        var copy = folder.appendingPathComponent(name + ".json")
        var attempt = 1
        while FileManager.default.fileExists(atPath: copy.path) {
            attempt += 1
            copy = folder.appendingPathComponent("\(name)-\(attempt).json")
        }
        try FileManager.default.copyItem(at: fileURL, to: copy)
        return copy
    }
}

/// The bytes a store last loaded or wrote. They have passed validation, so `save`
/// compares the file with them instead of decoding it again before each write.
private final class KnownContents: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    func matches(_ data: Data) -> Bool { lock.withLock { bytes == data } }
    func update(_ data: Data) { lock.withLock { bytes = data } }
}
