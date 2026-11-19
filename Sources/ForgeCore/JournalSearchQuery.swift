import Combine
import Foundation

/// The text a journal search field shows results for. Typing only records the text; the
/// search runs once typing pauses for `debounce`, away from the main actor, and the list
/// switches to the new text when its sessions are ready. Each keystroke cancels the search
/// before it, so the newest text always wins: a slower, older search can never replace it.
/// Clearing the field, or typing only spaces, shows every session at once.
@MainActor
public final class JournalSearchQuery: ObservableObject {
    /// The text the list's sessions are for. It trails `typed` while a search is pending.
    @Published public private(set) var applied = ""
    /// The text in the field.
    public private(set) var typed = ""
    /// Whether the list is still showing sessions for earlier text.
    public var isPending: Bool { applied != typed }
    public let debounce: Duration
    private var task: Task<Void, Never>?
    private var generation = 0

    public init(debounce: Duration = .milliseconds(100)) {
        self.debounce = debounce
    }

    /// Records `text` from the field. `isReady` says whether the sessions for some text are
    /// already at hand, so the list can switch without waiting. Otherwise, after the
    /// debounce, `prepare` finds and keeps them, returning false when what it found is out
    /// of date (saved progress changed meanwhile), in which case it is asked again.
    public func type(_ text: String, isReady: (String) -> Bool = { _ in false },
                     prepare: @escaping @MainActor (String) async -> Bool) {
        guard text != typed else { return }
        typed = text
        generation += 1
        task?.cancel()
        task = nil
        // No words lists every session, which needs no text search; the same words as the
        // list shows, or sessions already found, need no search either.
        let terms = SessionSearch(query: text).terms
        if terms.isEmpty || terms == SessionSearch(query: applied).terms || isReady(text) {
            applied = text
            return
        }
        let current = generation
        task = Task { [weak self, debounce] in
            if debounce > .zero {
                do { try await Task.sleep(for: debounce, tolerance: .milliseconds(5)) } catch { return }
            }
            for _ in 0..<3 {
                guard !Task.isCancelled else { return }
                if await prepare(text) { break }
            }
            // Only the search for the newest text may change what the list shows.
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.applied = text
            self.task = nil
        }
    }

    /// Stops a pending search, such as when the journal closes.
    public func cancel() {
        task?.cancel()
        task = nil
    }

    /// Waits for the pending search, if any, to finish or be cancelled. For checks.
    public func settle() async {
        while let task {
            await task.value
            if self.task == task { self.task = nil }
        }
    }
}
