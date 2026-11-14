import Foundation
import ForgeCore

/// Headless regressions for the shared editor state; no user data is touched.
@MainActor
enum NativeChecks {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(message) }
    }
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Forge-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let model = AppModel(progressURL: url, refreshCatalogOnLaunch: false)
        guard let catalog = model.curriculum, let lesson = catalog.modules.first else { throw Failure("Curriculum load failed") }
        try require(!model.readOnly, "Fresh store should be writable")
        model.noteDrafts[lesson.id] = "Invariant: the queue contains discovered, unprocessed vertices."
        model.destination = .journal
        model.openModule(lesson.id)
        try require(model.noteDrafts[lesson.id]?.hasPrefix("Invariant:") == true, "Navigation lost the note draft")
        try require(model.flushNotes(), "Pending note could not flush before backup")
        let reopened = AppModel(progressURL: url, refreshCatalogOnLaunch: false)
        try require(reopened.progress.notes[lesson.id] == model.noteDrafts[lesson.id], "Flushed draft did not survive restart")
        print("PASS shared draft survives navigation and restart")

        let before = try Data(contentsOf: url)
        model.noteDrafts[lesson.id] = String(repeating: "x", count: 20_001)
        try require(!model.flushNotes(), "Oversized draft unexpectedly saved")
        let after = try Data(contentsOf: url)
        try require(before == after, "Failed save altered the existing progress file")
        try require(model.noteDrafts[lesson.id]?.count == 20_001, "Failed save discarded the draft")
        print("PASS failed save retains draft and preserves disk")

        let store = ProgressFileStore(fileURL: url, allowedModuleIDs: catalog.moduleIDs)
        let restored = ProgressSnapshot(notes: [lesson.id: "Restored note"], dailyFocus: "Test the boundary")
        model.backupCandidate = try store.exportData(restored)
        model.confirmRestore()
        try require(model.noteDrafts[lesson.id] == "Restored note", "Restore left stale editor text")
        try require(model.focusDraft == "Test the boundary", "Restore left stale focus text")
        try require(model.flushNotes(), "Restored draft could not flush")
        let disk = try store.load()
        try require(disk.notes == restored.notes, "Draft flush overwrote restored notes")
        print("PASS restore replaces shared drafts before further saves")
        try require(LabBrowser.permitsFrame(URL(string: "about:srcdoc")!, isMainFrame: false), "Sandbox runner child frame was blocked")
        try require(!LabBrowser.permitsFrame(URL(string: "about:srcdoc")!, isMainFrame: true), "Top-level srcdoc was allowed")
        try require(!LabBrowser.permitsFrame(URL(string: "https://example.com/")!, isMainFrame: false), "Untrusted embedded navigation was allowed")
        try require(!LabBrowser.permitsFrame(URL(string: "javascript:alert(1)")!, isMainFrame: true), "Script navigation was allowed")
        print("PASS sandbox runner frame allowed with external navigation blocked")
        print("4/4 native regression checks passed")
    }
}

// Explicit continuations let these checks advance a refresh without waiting for a
// real timer or making a network request. The loader deliberately ignores task
// cancellation so a late response exercises the model's cancellation guard.
private actor ResourceRefreshLoader {
    private(set) var requestCount = 0
    private(set) var deliveredCount = 0
    private var pending: [Int: CheckedContinuation<ResourceCatalog, Error>] = [:]

    func load() async throws -> ResourceCatalog {
        requestCount += 1
        let request = requestCount
        let result: ResourceCatalog = try await withCheckedThrowingContinuation { pending[request] = $0 }
        deliveredCount += 1
        return result
    }

    func succeed(_ catalog: ResourceCatalog, request: Int) {
        pending.removeValue(forKey: request)?.resume(returning: catalog)
    }

    func fail(request: Int) { pending.removeValue(forKey: request)?.resume(throwing: URLError(.notConnectedToInternet)) }
    func cancelAll() {
        let outstanding = pending.values
        pending.removeAll()
        for continuation in outstanding { continuation.resume(throwing: CancellationError()) }
    }
}

private actor ResourceRefreshSleeper {
    private var pending: [(UUID, CheckedContinuation<Void, Error>)] = []
    private(set) var durations: [Duration] = []
    var pendingCount: Int { pending.count }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        durations.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { pending.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func wakeNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().1.resume()
    }

    private func cancel(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.0 == id }) else { return }
        pending.remove(at: index).1.resume(throwing: CancellationError())
    }

    func cancelAll() {
        let outstanding = pending
        pending.removeAll()
        for (_, continuation) in outstanding { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
private final class ResourceRefreshFixture {
    var now = Date(timeIntervalSince1970: 2_000_000_000)
    let loader = ResourceRefreshLoader()
    let sleeper = ResourceRefreshSleeper()
    let directory: URL
    var catalogURL: URL { directory.appendingPathComponent("catalog.json") }
    var progressURL: URL { directory.appendingPathComponent("progress.json") }
    private var models: [AppModel] = []

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Forge-resource-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func model(automatic: Bool = true, catalogURL: URL? = nil,
               interval: TimeInterval = 900, realSleep: Bool = false) -> AppModel {
        let loader = self.loader, sleeper = self.sleeper
        let model = AppModel(
            progressURL: progressURL, refreshCatalogOnLaunch: automatic,
            resourceCatalogURL: catalogURL ?? self.catalogURL, resourceRefreshInterval: interval,
            resourceNow: { [unowned self] in self.now },
            resourceSleep: { duration in
                if realSleep { try await Task.sleep(for: duration) }
                else { try await sleeper.sleep(duration) }
            },
            resourceLoader: { try await loader.load() }
        )
        models.append(model)
        return model
    }

    func close() {
        models.forEach { $0.stopResourceCatalogRefresh() }
        let loader = self.loader, sleeper = self.sleeper
        Task { await loader.cancelAll(); await sleeper.cancelAll() }
        try? FileManager.default.removeItem(at: directory)
    }
}

extension NativeChecks {
    private static func resourceSnapshot(_ title: String, day: Int) throws -> ResourceCatalog {
        let bundle = try ResourceCatalog.loadBundled()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bundle)) as! [String: Any]
        object["title"] = title
        object["fetchedAt"] = String(format: "2030-01-%02dT00:00:00Z", day)
        return try ResourceCatalog.decode(JSONSerialization.data(withJSONObject: object))
    }

    private static func eventually(_ message: String, _ predicate: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await predicate()) {
            if ContinuousClock.now >= deadline { throw Failure(message) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    static func runResourceRefresh() async throws {
        try await checkAutomaticResourceRefresh()
        try await checkOfflineResourceRestart()
        try await checkCorruptResourceCache()
        try await checkResourceSaveFailure()
        try await checkResourceCancellation()
        try await checkOlderResourceResponse()
        try await checkNewerResourceSavedDuringDownload()
        try await checkResourceRetry()
        try await checkResourceClockAdjustment()
        try await checkRealResourceTimer()
        print("10/10 native resource refresh checks passed")
    }

    private static func checkAutomaticResourceRefresh() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        try await eventually("Launch did not request the catalog") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("First download", day: 2), request: 1)
        try await eventually("Launch refresh did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "First download", "Launch response was not displayed")
        try require(model.resourceCatalogSavedOffline, "A downloaded catalog was not saved offline")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Successful check time is missing")
        try require(model.resourceCatalogNextRefreshAt == fixture.now.addingTimeInterval(900), "Next automatic check has the wrong deadline")
        try await eventually("No automatic refresh timer was armed") { await fixture.sleeper.pendingCount == 1 }
        let originalDeadline = model.resourceCatalogNextRefreshAt
        fixture.now.addTimeInterval(450)
        model.refreshResourceCatalogIfDue()
        try await eventually("Activation did not preserve a remaining timer") {
            let durations = await fixture.sleeper.durations
            let pending = await fixture.sleeper.pendingCount
            return durations.count == 2 && durations.last == .seconds(450) && pending == 1
        }
        let requestsBeforeDue = await fixture.loader.requestCount
        try require(requestsBeforeDue == 1 && model.resourceCatalogNextRefreshAt == originalDeadline, "Activation downloaded early or reset the refresh deadline")
        fixture.now.addTimeInterval(450)
        await fixture.sleeper.wakeNext()
        try await eventually("The timer did not refresh without a manual action") { await fixture.loader.requestCount == 2 }
        model.refreshResourceCatalog()
        model.refreshResourceCatalogIfDue()
        for _ in 0..<10 { await Task.yield() }
        let requests = await fixture.loader.requestCount
        try require(requests == 2, "Overlapping manual and due requests started duplicate downloads")
        await fixture.loader.succeed(try resourceSnapshot("Automatic update", day: 3), request: 2)
        try await eventually("Automatic refresh did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "Automatic update", "Automatic update was not displayed")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Automatic check did not advance its timestamp")
        print("PASS launch and periodic refresh run automatically; manual/due requests coalesce")
    }

    private static func checkOfflineResourceRestart() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let downloaded = try resourceSnapshot("Saved before restart", day: 5)
        _ = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).save(downloaded)
        let before = try Data(contentsOf: fixture.catalogURL)
        let model = fixture.model()
        try require(model.resourceCatalog?.title == downloaded.title, "Restart did not immediately open the latest saved catalog")
        try require(model.resourceCatalogSavedOffline, "Restart did not identify its saved offline snapshot")
        try await eventually("Restart did not try a refresh") { await fixture.loader.requestCount == 1 }
        await fixture.loader.fail(request: 1)
        try await eventually("Offline refresh did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == downloaded.title, "Network failure discarded the saved snapshot")
        try require(model.resourceCatalogRefreshNotice != nil, "Offline fallback did not explain the refresh failure")
        try require(model.resourceCatalogLastCheckedAt == nil, "Failed request claimed a successful metadata check")
        try require(!model.readOnly && model.message == nil, "Resource failure affected the learning progress store")
        let after = try Data(contentsOf: fixture.catalogURL)
        try require(before == after, "Offline startup changed the valid cache")
        print("PASS restart opens the last saved catalog and preserves it when offline")
    }

    private static func checkCorruptResourceCache() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let corrupt = Data("{broken catalog".utf8)
        try corrupt.write(to: fixture.catalogURL)
        let model = fixture.model(automatic: false)
        try require(model.resourceCatalog != nil, "Corrupt cache hid the bundled library")
        try require(model.resourceCatalogOrigin.localizedCaseInsensitiveContains("bundled"), "Corrupt cache was represented as a usable saved catalog")
        try require(!model.resourceCatalogSavedOffline, "Corrupt cache was reported as saved offline data")
        try require(model.resourceCatalogRefreshNotice != nil, "Corrupt cache did not produce a recovery notice")
        try require(!model.readOnly && model.message == nil, "Corrupt resource cache disabled progress saving")
        let preserved = try Data(contentsOf: fixture.catalogURL)
        try require(preserved == corrupt, "Opening the app changed a corrupt cache before a verified replacement")
        model.refreshResourceCatalog()
        try await eventually("Manual recovery did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Recovered catalog", day: 6), request: 1)
        try await eventually("Manual recovery did not complete") { !model.isRefreshingResourceCatalog }
        let repaired = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).load()
        try require(repaired?.title == "Recovered catalog" && model.resourceCatalogSavedOffline, "Verified response did not repair the corrupt cache")
        try require(model.resourceCatalogRefreshNotice == nil, "Successful recovery left a stale warning")
        print("PASS corrupt cache falls back honestly and a verified refresh repairs it")
    }

    private static func checkResourceSaveFailure() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let blockedParent = fixture.directory.appendingPathComponent("not-a-directory")
        try Data("keep me".utf8).write(to: blockedParent)
        let blockedURL = blockedParent.appendingPathComponent("catalog.json")
        let model = fixture.model(automatic: false, catalogURL: blockedURL)
        try require(model.update { $0.dailyFocus = "Progress remains independent" }, "Could not write isolated test progress")
        let progressBefore = try Data(contentsOf: fixture.progressURL)
        model.refreshResourceCatalog()
        try await eventually("Save-failure refresh did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Session only", day: 7), request: 1)
        try await eventually("Save-failure refresh did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "Session only", "Disk failure discarded usable downloaded data")
        try require(!model.resourceCatalogSavedOffline, "Disk failure incorrectly promised offline availability")
        try require(model.resourceCatalogRefreshNotice != nil, "Disk failure was not disclosed")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Valid download lost its successful-check timestamp")
        let progressAfter = try Data(contentsOf: fixture.progressURL)
        let blockerAfter = try Data(contentsOf: blockedParent)
        try require(progressBefore == progressAfter && blockerAfter == Data("keep me".utf8), "Cache save failure changed unrelated disk data")
        print("PASS failed cache save keeps session data and reports that it is not saved offline")
    }

    private static func checkResourceCancellation() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        let originalTitle = model.resourceCatalog?.title
        try await eventually("Cancelable request did not start") { await fixture.loader.requestCount == 1 }
        model.stopResourceCatalogRefresh()
        try require(!model.isRefreshingResourceCatalog && model.resourceCatalogNextRefreshAt == nil, "Stopping refresh did not clear its active state and timer")
        model.refreshResourceCatalog()
        try await eventually("New manual refresh did not start after cancellation") { await fixture.loader.requestCount == 2 }
        await fixture.loader.succeed(try resourceSnapshot("Canceled late response", day: 9), request: 1)
        try await eventually("Canceled loader did not deliver its test response") { await fixture.loader.deliveredCount == 1 }
        for _ in 0..<10 { await Task.yield() }
        try require(model.resourceCatalog?.title == originalTitle, "Canceled response changed the displayed catalog")
        try require(model.isRefreshingResourceCatalog, "Canceled response cleared a newer in-flight refresh")
        try require(!FileManager.default.fileExists(atPath: fixture.catalogURL.path), "Canceled response was persisted")
        await fixture.loader.succeed(try resourceSnapshot("New manual response", day: 10), request: 2)
        try await eventually("New request did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "New manual response", "Current response was lost after canceling an earlier request")
        let persisted = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).load()
        try require(persisted?.title == "New manual response", "Late canceled response replaced the offline snapshot")
        try require(model.resourceCatalogNextRefreshAt == nil, "Manual refresh restarted a stopped automatic timer")
        print("PASS cancellation rejects late delivery without disturbing a newer manual request")
    }

    private static func checkOlderResourceResponse() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        _ = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).save(resourceSnapshot("Newest saved catalog", day: 15))
        let before = try Data(contentsOf: fixture.catalogURL)
        let model = fixture.model()
        try await eventually("Older-response check did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Older CDN response", day: 14), request: 1)
        try await eventually("Older-response check did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "Newest saved catalog", "Older CDN data replaced a newer local snapshot")
        try require(model.resourceCatalogSavedOffline, "Rejecting an older response lost offline availability")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Validated older response did not record its check time")
        let after = try Data(contentsOf: fixture.catalogURL)
        try require(before == after, "Older CDN data overwrote the newer disk cache")
        print("PASS older CDN response preserves the newer displayed and saved snapshot")
    }

    private static func checkResourceRetry() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        try await eventually("Initial retry fixture request did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Before network outage", day: 20), request: 1)
        try await eventually("First retry fixture response did not finish") { !model.isRefreshingResourceCatalog }
        try await eventually("First periodic timer did not arm") { await fixture.sleeper.pendingCount == 1 }
        let saved = try Data(contentsOf: fixture.catalogURL)
        fixture.now.addTimeInterval(900)
        await fixture.sleeper.wakeNext()
        try await eventually("Periodic outage request did not start") { await fixture.loader.requestCount == 2 }
        await fixture.loader.fail(request: 2)
        try await eventually("Failed periodic request did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalogRefreshNotice != nil && model.resourceCatalogSavedOffline, "Outage did not preserve and explain the saved fallback")
        try require(model.resourceCatalogNextRefreshAt == fixture.now.addingTimeInterval(900), "Outage did not schedule a bounded retry")
        let unchanged = try Data(contentsOf: fixture.catalogURL)
        try require(saved == unchanged, "Failed periodic fetch altered the cache")
        try await eventually("Retry timer was not armed after failure") { await fixture.sleeper.pendingCount == 1 }
        fixture.now.addTimeInterval(900)
        await fixture.sleeper.wakeNext()
        try await eventually("Retry did not run automatically") { await fixture.loader.requestCount == 3 }
        await fixture.loader.succeed(try resourceSnapshot("After automatic recovery", day: 21), request: 3)
        try await eventually("Automatic recovery did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "After automatic recovery" && model.resourceCatalogRefreshNotice == nil, "Automatic recovery retained stale content or warning")
        model.stopResourceCatalogRefresh()
        try await eventually("Stopping refresh left a periodic sleeper alive") { await fixture.sleeper.pendingCount == 0 }
        print("PASS periodic failure keeps offline data and automatically retries successfully")
    }

    private static func checkNewerResourceSavedDuringDownload() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        try await eventually("Concurrent-save fixture request did not start") { await fixture.loader.requestCount == 1 }
        // Another app instance writes newer data while this model still has its bundle.
        _ = try ResourceCatalogFileStore(fileURL: fixture.catalogURL).save(resourceSnapshot("Saved by another instance", day: 27))
        let before = try Data(contentsOf: fixture.catalogURL)
        await fixture.loader.succeed(try resourceSnapshot("In-flight older download", day: 26), request: 1)
        try await eventually("Concurrent-save response did not finish") { !model.isRefreshingResourceCatalog }
        try require(model.resourceCatalog?.title == "Saved by another instance", "Concurrent newer disk data did not replace the in-flight response")
        try require(model.resourceCatalogSavedOffline && model.resourceCatalogOrigin.localizedCaseInsensitiveContains("saved"), "Concurrent newer catalog was not identified as saved offline data")
        try require(model.resourceCatalogLastCheckedAt == fixture.now, "Concurrent disk recovery lost its successful check time")
        let after = try Data(contentsOf: fixture.catalogURL)
        try require(before == after, "In-flight download overwrote a newer concurrent cache save")
        print("PASS newer catalog saved during a download wins on disk and in the displayed library")
    }

    private static func checkResourceClockAdjustment() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model()
        try await eventually("Clock-adjustment fixture did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Before clock change", day: 22), request: 1)
        try await eventually("Clock-adjustment response did not finish") { !model.isRefreshingResourceCatalog }
        try await eventually("Clock-adjustment timer was not armed") { await fixture.sleeper.pendingCount == 1 }
        fixture.now.addTimeInterval(-3600)
        model.refreshResourceCatalogIfDue()
        try require(model.resourceCatalogNextRefreshAt == fixture.now.addingTimeInterval(900), "Backward clock change postponed the next refresh by more than one interval")
        try await eventually("Clock-adjustment timer was not replaced") {
            let durations = await fixture.sleeper.durations
            let pending = await fixture.sleeper.pendingCount
            return durations.count == 2 && pending == 1
        }
        // The monotonic timer elapsed even though the wall clock has not caught up.
        await fixture.sleeper.wakeNext()
        try await eventually("Elapsed timer was suppressed by a backward wall clock") { await fixture.loader.requestCount == 2 }
        model.stopResourceCatalogRefresh()
        print("PASS backward clock changes cannot postpone or suppress an elapsed refresh timer")
    }

    private static func checkRealResourceTimer() async throws {
        let fixture = try ResourceRefreshFixture()
        defer { fixture.close() }
        let model = fixture.model(interval: 0.1, realSleep: true)
        try await eventually("Real-timer launch request did not start") { await fixture.loader.requestCount == 1 }
        await fixture.loader.succeed(try resourceSnapshot("Before real timer", day: 23), request: 1)
        // No manual refresh, fake-clock advance, or continuation wake occurs here.
        try await eventually("Real Task.sleep timer did not start an automatic refresh") { await fixture.loader.requestCount == 2 }
        await fixture.loader.succeed(try resourceSnapshot("After real timer", day: 24), request: 2)
        try await eventually("Real-timer response did not finish") { !model.isRefreshingResourceCatalog }
        model.stopResourceCatalogRefresh()
        try require(model.resourceCatalog?.title == "After real timer", "Real timer did not display its downloaded update")
        let fakeSleeps = await fixture.sleeper.durations
        try require(fakeSleeps.isEmpty, "Real-timer check accidentally used the fake sleeper")
        print("PASS real elapsed-time scheduler refreshes automatically while the model is alive")
    }
}
