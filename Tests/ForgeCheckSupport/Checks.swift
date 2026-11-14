import Foundation
import ForgeCore

public enum ForgeCoreChecks {
    public static let names: [String] = [
        "testBundledGitHubCatalogAndSearch",
        "testGitHubCatalogRejectsUnsafeLinksAndDuplicateEntries",
        "testRemoteGitHubCatalogDownloadsAndValidates",
        "testRemoteGitHubCatalogRejectsUnsafeResponses",
        "testGitHubCatalogAgeHonesty",
        "testBundledCurriculumHasCompleteLearningPath",
        "testNewStoreIsEmptyWithoutCreatingFile",
        "testProgressSurvivesNewStoreInstanceAndBackupRoundTrip",
        "testImportOnlyValidatesUntilUserChoosesToRestore",
        "testMalformedAndTruncatedBackupsAreRejected",
        "testUnknownVersionsAndModuleIDsAreRejected",
        "testSessionDurationAndDuplicateIDsAreValidated",
        "testInvalidSessionDatesAreRejected",
        "testTextLimitsCountUTF8Bytes",
        "testOversizedBackupRejectedBeforeDecoding",
        "testInvalidSavePreservesPreviousSnapshotBytes",
        "testDamagedFileIsPreservedAndNotSilentlyReset",
        "testExplicitRecoveryPreservesDamagedOriginalAndRestoresBackup",
        "testInvalidRecoveryDoesNotTouchExistingData",
        "testReadOnlyDestinationFailsWithoutReportingSuccess",
        "testCalendarTotalsUseLearnersTimezone",
        "testDailyTotalsPreserveOrderAndTimezone",
        "testDailyTotalsHandleDaylightSavingTransitions",
        "testDailyTotalsHandleMaximumSessionHistory",
        "testSessionSearchCombinesTermsLessonsAndDateBounds"
]

    public static func run(_ name: String) throws {
        let cases = CoreCases()
        try cases.setUpWithError()
        defer { try? cases.tearDownWithError() }
        switch name {
        case "testBundledGitHubCatalogAndSearch": try cases.testBundledGitHubCatalogAndSearch()
        case "testGitHubCatalogRejectsUnsafeLinksAndDuplicateEntries": try cases.testGitHubCatalogRejectsUnsafeLinksAndDuplicateEntries()
        case "testRemoteGitHubCatalogDownloadsAndValidates": try cases.testRemoteGitHubCatalogDownloadsAndValidates()
        case "testRemoteGitHubCatalogRejectsUnsafeResponses": try cases.testRemoteGitHubCatalogRejectsUnsafeResponses()
        case "testGitHubCatalogAgeHonesty": try cases.testGitHubCatalogAgeHonesty()
        case "testBundledCurriculumHasCompleteLearningPath": try cases.testBundledCurriculumHasCompleteLearningPath()
        case "testNewStoreIsEmptyWithoutCreatingFile": try cases.testNewStoreIsEmptyWithoutCreatingFile()
        case "testProgressSurvivesNewStoreInstanceAndBackupRoundTrip": try cases.testProgressSurvivesNewStoreInstanceAndBackupRoundTrip()
        case "testImportOnlyValidatesUntilUserChoosesToRestore": try cases.testImportOnlyValidatesUntilUserChoosesToRestore()
        case "testMalformedAndTruncatedBackupsAreRejected": try cases.testMalformedAndTruncatedBackupsAreRejected()
        case "testUnknownVersionsAndModuleIDsAreRejected": try cases.testUnknownVersionsAndModuleIDsAreRejected()
        case "testSessionDurationAndDuplicateIDsAreValidated": try cases.testSessionDurationAndDuplicateIDsAreValidated()
        case "testInvalidSessionDatesAreRejected": try cases.testInvalidSessionDatesAreRejected()
        case "testTextLimitsCountUTF8Bytes": try cases.testTextLimitsCountUTF8Bytes()
        case "testOversizedBackupRejectedBeforeDecoding": try cases.testOversizedBackupRejectedBeforeDecoding()
        case "testInvalidSavePreservesPreviousSnapshotBytes": try cases.testInvalidSavePreservesPreviousSnapshotBytes()
        case "testDamagedFileIsPreservedAndNotSilentlyReset": try cases.testDamagedFileIsPreservedAndNotSilentlyReset()
        case "testExplicitRecoveryPreservesDamagedOriginalAndRestoresBackup": try cases.testExplicitRecoveryPreservesDamagedOriginalAndRestoresBackup()
        case "testInvalidRecoveryDoesNotTouchExistingData": try cases.testInvalidRecoveryDoesNotTouchExistingData()
        case "testReadOnlyDestinationFailsWithoutReportingSuccess": try cases.testReadOnlyDestinationFailsWithoutReportingSuccess()
        case "testCalendarTotalsUseLearnersTimezone": try cases.testCalendarTotalsUseLearnersTimezone()
        case "testDailyTotalsPreserveOrderAndTimezone": try cases.testDailyTotalsPreserveOrderAndTimezone()
        case "testDailyTotalsHandleDaylightSavingTransitions": try cases.testDailyTotalsHandleDaylightSavingTransitions()
        case "testDailyTotalsHandleMaximumSessionHistory": try cases.testDailyTotalsHandleMaximumSessionHistory()
        case "testSessionSearchCombinesTermsLessonsAndDateBounds": try cases.testSessionSearchCombinesTermsLessonsAndDateBounds()
        default: throw CheckFailure(description: "Unknown check: \(name)")
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T,
                                         _ rhs: @autoclosure () throws -> T,
                                         file: StaticString = #filePath, line: UInt = #line) throws {
    let left = try lhs(), right = try rhs()
    guard left == right else { throw CheckFailure(description: "Expected equal values at \(file):\(line)") }
}

private func XCTAssertTrue(_ value: @autoclosure () throws -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) throws {
    guard try value() else { throw CheckFailure(description: "Expected true at \(file):\(line)") }
}

private func XCTAssertFalse(_ value: @autoclosure () throws -> Bool,
                            file: StaticString = #filePath, line: UInt = #line) throws {
    guard try !value() else { throw CheckFailure(description: "Expected false at \(file):\(line)") }
}

private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T,
                                    _ verify: ((Error) throws -> Void)? = nil,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
    do { _ = try expression() }
    catch { try verify?(error); return }
    throw CheckFailure(description: "Expected an error at \(file):\(line)")
}

private func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T) throws {
    _ = try expression()
}

private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure(description: "Unexpected nil") }
    return value
}

private final class CoreCases {
    private var directory: URL!
    private var store: ProgressFileStore!

    func testBundledGitHubCatalogAndSearch() throws {
        let catalog = try ResourceCatalog.loadBundled()
        try XCTAssertEqual(catalog.project, "forge-macos")
        try XCTAssertTrue(!catalog.items.isEmpty)
        let first = try XCTUnwrap(catalog.items.first)
        try XCTAssertTrue(catalog.matching(first.fullName).contains { $0.id == first.id })
        try XCTAssertTrue(catalog.matching("", category: first.category).allSatisfy { $0.category == first.category })
        try XCTAssertTrue(catalog.matching("there-is-no-project-with-this-name").isEmpty)
    }

    func testGitHubCatalogRejectsUnsafeLinksAndDuplicateEntries() throws {
        let item: [String: Any] = ["fullName": "python/cpython", "url": "https://github.com/python/cpython", "description": "Python language", "topics": ["python"], "stars": NSNull(), "license": NSNull(), "category": "languages", "fetchedAt": NSNull(), "stale": false]
        var document: [String: Any] = ["schemaVersion": 1, "project": "forge-macos", "title": "Resources", "fetchedAt": NSNull(), "status": "seed", "categories": [["id": "languages", "title": "Languages"]], "items": [item]]
        let valid = try ResourceCatalog.decode(JSONSerialization.data(withJSONObject: document))
        try XCTAssertEqual(valid.items.first?.stars, nil)
        for url in ["javascript:alert(1)", "https://example.com/python/cpython", "https://github.com@evil.example/python/cpython", "https://github.com/python/cpython?token=example"] {
            var unsafe = item
            unsafe["url"] = url
            document["items"] = [unsafe]
            try XCTAssertThrowsError(ResourceCatalog.decode(JSONSerialization.data(withJSONObject: document)))
        }
        document["items"] = [item, item]
        try XCTAssertThrowsError(ResourceCatalog.decode(JSONSerialization.data(withJSONObject: document)))
        document["items"] = [item]
        document["schemaVersion"] = 2
        try XCTAssertThrowsError(ResourceCatalog.decode(JSONSerialization.data(withJSONObject: document)))
    }

    func testRemoteGitHubCatalogDownloadsAndValidates() throws {
        let local = try ResourceCatalog.loadBundled()
        let data = try catalogFixtureData()
        let downloaded = try fetchCatalogFixture(data)
        try XCTAssertEqual(downloaded.project, local.project)
        try XCTAssertEqual(downloaded.items.first?.fullName, "python/cpython")
        try XCTAssertEqual(CatalogFixtureProtocol.requestedURL, ResourceCatalog.latestURL)
    }

    func testRemoteGitHubCatalogRejectsUnsafeResponses() throws {
        let data = try catalogFixtureData()
        try XCTAssertThrowsError(fetchCatalogFixture(data, status: 503))
        try XCTAssertThrowsError(fetchCatalogFixture(data, status: 302))
        try XCTAssertThrowsError(fetchCatalogFixture(data, declaredSize: ResourceCatalog.maximumDownloadBytes + 1))
        try XCTAssertThrowsError(fetchCatalogFixture(Data(repeating: 32, count: ResourceCatalog.maximumDownloadBytes + 1)))
        try XCTAssertThrowsError(fetchCatalogFixture(Data("{}".utf8)))
        try XCTAssertThrowsError(fetchCatalogFixture(data, error: URLError(.notConnectedToInternet)))
    }

    func testGitHubCatalogAgeHonesty() throws {
        let catalog = try ResourceCatalog.decode(catalogFixtureData())
        let resource = try XCTUnwrap(catalog.items.first)
        let formatter = ISO8601DateFormatter()
        let fresh = try XCTUnwrap(formatter.date(from: "2026-11-14T01:00:00Z"))
        let old = try XCTUnwrap(formatter.date(from: "2026-11-16T00:00:00Z"))
        try XCTAssertFalse(resource.isStale(at: fresh))
        try XCTAssertTrue(resource.isStale(at: old))
    }

    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ForgeCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ProgressFileStore(fileURL: directory.appendingPathComponent("nested/progress.json"),
                                  allowedModuleIDs: try Curriculum.loadBundled().moduleIDs)
    }

    func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    func testBundledCurriculumHasCompleteLearningPath() throws {
        let curriculum = try Curriculum.loadBundled()
        try XCTAssertEqual(curriculum.phases.count, 10)
        try XCTAssertEqual(curriculum.modules.count, 50)
        try XCTAssertEqual(curriculum.moduleIDs.count, 50)
        try XCTAssertEqual(curriculum.totalHours, 2_000)
        try XCTAssertEqual(curriculum.modules.reduce(0) { $0 + $1.hours }, 2_000)
        try XCTAssertEqual(curriculum.problems.count, 36)
        try XCTAssertTrue(curriculum.modules.allSatisfy { !$0.task.isEmpty && !$0.successCriteria.isEmpty })
        try XCTAssertTrue(curriculum.resources.allSatisfy { $0.url.scheme == "https" })
    }

    func testNewStoreIsEmptyWithoutCreatingFile() throws {
        try XCTAssertEqual(try store.load(), ProgressSnapshot())
        try XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testProgressSurvivesNewStoreInstanceAndBackupRoundTrip() throws {
        let original = sampleSnapshot()
        try store.save(original)
        let restarted = ProgressFileStore(fileURL: store.fileURL, allowedModuleIDs: store.allowedModuleIDs)
        try XCTAssertEqual(try restarted.load(), original)
        let exported = try restarted.exportData(original)
        try XCTAssertEqual(try restarted.importData(exported), original)
    }

    func testImportOnlyValidatesUntilUserChoosesToRestore() throws {
        let original = sampleSnapshot()
        let data = try store.exportData(original)
        try XCTAssertEqual(try store.importData(data), original)
        try XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testMalformedAndTruncatedBackupsAreRejected() throws {
        for data in [Data(), Data("{}".utf8), Data("{\"version\":1".utf8), Data("[]".utf8)] {
            try XCTAssertThrowsError(try store.importData(data)) { try XCTAssertEqual($0 as? ProgressError, .invalidBackup) }
        }
    }

    func testUnknownVersionsAndModuleIDsAreRejected() throws {
        var snapshot = sampleSnapshot()
        snapshot.version = 99
        try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .unsupportedVersion) }
        snapshot.version = 1
        snapshot.completedModuleIDs.insert("not-a-lesson")
        try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .invalidModule) }
        snapshot = sampleSnapshot()
        snapshot.notes["not-a-lesson"] = "unexpected"
        try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .invalidModule) }
        snapshot = sampleSnapshot()
        snapshot.sessions[0].moduleID = "not-a-lesson"
        try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .invalidModule) }
    }

    func testSessionDurationAndDuplicateIDsAreValidated() throws {
        for minutes in [-1, 0, 721, Int.max] {
            var snapshot = sampleSnapshot()
            snapshot.sessions[0].minutes = minutes
            try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .invalidSession) }
        }
        var snapshot = sampleSnapshot()
        snapshot.sessions.append(snapshot.sessions[0])
        try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .invalidSession) }
        snapshot = sampleSnapshot()
        snapshot.sessions[0].minutes = 720
        try XCTAssertNoThrow(try store.exportData(snapshot))
    }

    func testInvalidSessionDatesAreRejected() throws {
        for date in [Date(timeIntervalSince1970: -1), Date(timeIntervalSince1970: .infinity)] {
            var snapshot = sampleSnapshot()
            snapshot.sessions[0].date = date
            try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .invalidSession) }
        }
    }

    func testTextLimitsCountUTF8Bytes() throws {
        var snapshot = sampleSnapshot()
        snapshot.dailyFocus = String(repeating: "é", count: 1_001)
        try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .textLimit) }
        snapshot = sampleSnapshot()
        snapshot.notes["f01"] = String(repeating: "a", count: 20_001)
        try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .textLimit) }
        snapshot = sampleSnapshot()
        snapshot.sessions[0].reflection = String(repeating: "a", count: 20_001)
        try XCTAssertThrowsError(try store.exportData(snapshot)) { try XCTAssertEqual($0 as? ProgressError, .textLimit) }
    }

    func testOversizedBackupRejectedBeforeDecoding() throws {
        try XCTAssertThrowsError(try store.importData(Data(repeating: 32, count: ProgressFileStore.maximumBackupBytes + 1))) {
            try XCTAssertEqual($0 as? ProgressError, .oversizedBackup)
        }
    }

    func testInvalidSavePreservesPreviousSnapshotBytes() throws {
        let original = sampleSnapshot()
        try store.save(original)
        let bytes = try Data(contentsOf: store.fileURL)
        var invalid = original
        invalid.sessions[0].minutes = 0
        try XCTAssertThrowsError(try store.save(invalid))
        try XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
        try XCTAssertEqual(try store.load(), original)
    }

    func testDamagedFileIsPreservedAndNotSilentlyReset() throws {
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let damaged = Data("interrupted or damaged storage".utf8)
        try damaged.write(to: store.fileURL)
        try XCTAssertThrowsError(try store.load())
        try XCTAssertThrowsError(try store.save(ProgressSnapshot())) {
            try XCTAssertEqual($0 as? ProgressError, .damagedExistingFile)
        }
        try XCTAssertEqual(try Data(contentsOf: store.fileURL), damaged)
    }

    func testExplicitRecoveryPreservesDamagedOriginalAndRestoresBackup() throws {
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let damaged = Data("damaged original".utf8)
        try damaged.write(to: store.fileURL)
        let original = sampleSnapshot()
        let data = try store.exportData(original)
        try XCTAssertEqual(try store.recoverFromBackup(data), original)
        try XCTAssertEqual(try store.load(), original)
        let preserved = try FileManager.default.contentsOfDirectory(at: store.fileURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("progress-before-restore-") }
        try XCTAssertEqual(preserved.count, 1)
        try XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(preserved.first)), damaged)
    }

    func testInvalidRecoveryDoesNotTouchExistingData() throws {
        try store.save(sampleSnapshot())
        let before = try Data(contentsOf: store.fileURL)
        try XCTAssertThrowsError(try store.recoverFromBackup(Data("{}".utf8)))
        try XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
        try XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path), ["progress.json"])
    }

    func testReadOnlyDestinationFailsWithoutReportingSuccess() throws {
        // A regular file cannot contain the progress file. This deterministically
        // simulates a failed storage destination without relying on Unix modes.
        let blocker = directory.appendingPathComponent("not-a-folder")
        try Data("preserve me".utf8).write(to: blocker)
        let failing = ProgressFileStore(fileURL: blocker.appendingPathComponent("progress.json"),
                                       allowedModuleIDs: store.allowedModuleIDs)
        try XCTAssertThrowsError(try failing.save(sampleSnapshot()))
        try XCTAssertEqual(try Data(contentsOf: blocker), Data("preserve me".utf8))
    }

    func testCalendarTotalsUseLearnersTimezone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let formatter = ISO8601DateFormatter()
        let beforeMidnight = try XCTUnwrap(formatter.date(from: "2026-10-29T18:20:00Z"))
        let afterMidnight = try XCTUnwrap(formatter.date(from: "2026-10-29T18:40:00Z"))
        let snapshot = ProgressSnapshot(completedModuleIDs: ["f01", "f02"], sessions: [
            StudySession(date: beforeMidnight, minutes: 25, reflection: "Paths"),
            StudySession(date: afterMidnight, minutes: 45, reflection: "Testing")
        ])
        try XCTAssertEqual(snapshot.totalMinutes, 70)
        try XCTAssertEqual(snapshot.minutes(on: beforeMidnight, calendar: calendar), 25)
        try XCTAssertEqual(snapshot.minutes(on: afterMidnight, calendar: calendar), 45)
        try XCTAssertEqual(snapshot.completedHours(in: try Curriculum.loadBundled()), 32)
    }

    func testDailyTotalsPreserveOrderAndTimezone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let formatter = ISO8601DateFormatter()
        let before = try XCTUnwrap(formatter.date(from: "2026-10-29T18:20:00Z"))
        let after = try XCTUnwrap(formatter.date(from: "2026-10-29T18:40:00Z"))
        let empty = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: after))
        let snapshot = ProgressSnapshot(sessions: [
            StudySession(date: before, minutes: 25, reflection: "Before midnight"),
            StudySession(date: after, minutes: 45, reflection: "After midnight")
        ])
        try XCTAssertEqual(snapshot.minutes(on: [after, empty, before, after], calendar: calendar), [45, 0, 25, 45])
        try XCTAssertEqual(snapshot.minutes(on: [], calendar: calendar), [])
        try XCTAssertEqual(ProgressSnapshot().minutes(on: [before, after], calendar: calendar), [0, 0])
    }

    func testDailyTotalsHandleDaylightSavingTransitions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let formatter = ISO8601DateFormatter()
        // Both 01:30 occurrences on the 25-hour autumn day belong to one bar;
        // the 23-hour spring day also includes its final half-hour.
        for (dates, expected) in [
            (["2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", "2026-11-02T04:30:00Z", "2026-11-02T05:00:00Z"], [60, 40]),
            (["2026-03-08T06:30:00Z", "2026-03-08T07:30:00Z", "2026-03-09T03:30:00Z", "2026-03-09T04:00:00Z"], [60, 40])
        ] {
            let instants = try dates.map { try XCTUnwrap(formatter.date(from: $0)) }
            let snapshot = ProgressSnapshot(sessions: instants.enumerated().map { index, date in
                StudySession(date: date, minutes: (index + 1) * 10, reflection: "Boundary")
            })
            try XCTAssertEqual(snapshot.minutes(on: [instants[0], instants[3]], calendar: calendar), expected)
        }
    }

    func testDailyTotalsHandleMaximumSessionHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = Date(timeIntervalSince1970: 1_793_275_200)
        let days = try (0..<7).map { try XCTUnwrap(calendar.date(byAdding: .day, value: $0, to: start)) }
        var expected = Array(repeating: 0, count: days.count)
        let sessions = (0..<20_000).map { index in
            expected[index % days.count] += 25
            return StudySession(date: days[index % days.count], minutes: 25, reflection: "Practice")
        }
        let snapshot = ProgressSnapshot(sessions: sessions)
        try store.validate(snapshot)
        try XCTAssertEqual(snapshot.minutes(on: days, calendar: calendar), expected)
        try XCTAssertEqual(snapshot.minutes(on: Array(days.reversed()), calendar: calendar), Array(expected.reversed()))
    }

    func testSessionSearchCombinesTermsLessonsAndDateBounds() throws {
        let start = Date(timeIntervalSince1970: 1_793_275_200)
        let older = StudySession(date: start.addingTimeInterval(-1), minutes: 10, reflection: "Queue invariant", moduleID: "f01")
        let current = StudySession(date: start, minutes: 20, reflection: "Queue invariant", moduleID: "f01")
        let independent = StudySession(date: start.addingTimeInterval(60), minutes: 30, reflection: "Refined proof")
        let next = StudySession(date: start.addingTimeInterval(86_400), minutes: 40, reflection: "Queue invariant", moduleID: "f01")
        let snapshot = ProgressSnapshot(sessions: [current, older, next, independent])
        try XCTAssertEqual(snapshot.filteredSessions(query: " QUEUE   graphs ", since: start, before: next.date, moduleTitles: ["f01": "Graphs and BFS"]), [current])
        try XCTAssertEqual(snapshot.filteredSessions(moduleID: ""), [independent])
        try XCTAssertEqual(snapshot.filteredSessions(query: "independent proof"), [independent])
        try XCTAssertEqual(snapshot.filteredSessions(moduleID: "missing"), [])
        try XCTAssertEqual(snapshot.filteredSessions().map(\.id), [next.id, independent.id, current.id, older.id])
        try XCTAssertEqual(snapshot.sessions, [current, older, next, independent])
        try XCTAssertEqual(snapshot.totalMinutes, 100)
    }

    private func sampleSnapshot() -> ProgressSnapshot {
        ProgressSnapshot(completedModuleIDs: ["f01"], notes: ["f01": "A file is stored; a process runs."],
                         dailyFocus: "Explain paths", sessions: [
                            StudySession(id: UUID(uuidString: "48777513-9059-44AB-B5AF-B5BC3EC7D266")!,
                                         date: Date(timeIntervalSince1970: 1_793_275_200),
                                         minutes: 25, reflection: "Ran the script twice", moduleID: "f01")
                         ])
    }
}

private func catalogFixtureData() throws -> Data {
    let item: [String: Any] = ["fullName": "python/cpython", "url": "https://github.com/python/cpython", "description": "Python language", "topics": ["python"], "stars": 100, "license": NSNull(), "category": "languages", "fetchedAt": "2026-11-14T00:00:00.000Z", "stale": false]
    let document: [String: Any] = ["schemaVersion": 1, "project": "forge-macos", "title": "Resources", "fetchedAt": "2026-11-14T00:00:00.000Z", "status": "live", "categories": [["id": "languages", "title": "Languages"]], "items": [item]]
    return try JSONSerialization.data(withJSONObject: document)
}

private final class CatalogFixtureProtocol: URLProtocol, @unchecked Sendable {
    static var bytes = Data()
    static var status = 200
    static var declaredSize: Int?
    static var transportError: URLError?
    static var requestedURL: URL?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestedURL = request.url
        if let error = Self.transportError { client?.urlProtocol(self, didFailWithError: error); return }
        var headers = ["Content-Type": "application/json"]
        if let size = Self.declaredSize { headers["Content-Length"] = String(size) }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class CatalogFixtureResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<ResourceCatalog, Error>?
    func set(_ value: Result<ResourceCatalog, Error>) { lock.lock(); defer { lock.unlock() }; result = value }
    func get() throws -> ResourceCatalog { lock.lock(); defer { lock.unlock() }; return try result!.get() }
}

private func fetchCatalogFixture(_ data: Data, status: Int = 200, declaredSize: Int? = nil, error: URLError? = nil) throws -> ResourceCatalog {
    CatalogFixtureProtocol.bytes = data
    CatalogFixtureProtocol.status = status
    CatalogFixtureProtocol.declaredSize = declaredSize
    CatalogFixtureProtocol.transportError = error
    CatalogFixtureProtocol.requestedURL = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogFixtureProtocol.self]
    let box = CatalogFixtureResult()
    let done = DispatchSemaphore(value: 0)
    let task = Task.detached {
        do { box.set(.success(try await ResourceCatalog.loadLatest(configuration: configuration))) }
        catch { box.set(.failure(error)) }
        done.signal()
    }
    if done.wait(timeout: .now() + 10) != .success {
        task.cancel()
        throw CheckFailure(description: "Fixture catalog request exceeded its deadline")
    }
    return try box.get()
}
