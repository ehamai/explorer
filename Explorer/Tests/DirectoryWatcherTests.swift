import Testing
import Foundation
@testable import Explorer

private actor CallbackTracker {
    var callCount = 0
    var called: Bool { callCount > 0 }
    func increment() { callCount += 1 }
}

@Suite("DirectoryWatcher")
struct DirectoryWatcherTests {

    @Test func onChangeFiresOnFileCreation() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let tracker = CallbackTracker()
        let watcher = DirectoryWatcher()
        watcher.onChange = { Task { await tracker.increment() } }
        watcher.watch(url: dir)

        _ = try TestHelpers.createFile("new.txt", in: dir)

        try await Task.sleep(for: .seconds(2))
        let wasCalled = await tracker.called
        #expect(wasCalled)
        watcher.stop()
    }

    @Test func stopPreventsCallback() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let tracker = CallbackTracker()
        let watcher = DirectoryWatcher()
        watcher.onChange = { Task { await tracker.increment() } }
        watcher.watch(url: dir)
        watcher.stop()

        _ = try TestHelpers.createFile("after-stop.txt", in: dir)

        try await Task.sleep(for: .seconds(1))
        let wasCalled = await tracker.called
        #expect(!wasCalled)
    }

    @Test func watchNewDirStopsOld() async throws {
        let dir1 = try TestHelpers.makeTempDir()
        let dir2 = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir1); TestHelpers.cleanup(dir2) }

        let tracker = CallbackTracker()
        let watcher = DirectoryWatcher()
        watcher.onChange = { Task { await tracker.increment() } }
        watcher.watch(url: dir1)

        // Switch to watching dir2 — should stop watching dir1
        watcher.watch(url: dir2)

        // Create file in dir1 — should NOT trigger callback
        _ = try TestHelpers.createFile("old-dir.txt", in: dir1)

        try await Task.sleep(for: .seconds(1))
        let wasCalled = await tracker.called
        #expect(!wasCalled)
        watcher.stop()
    }

    @Test func watchInvalidPathDoesNotCrash() async throws {
        let watcher = DirectoryWatcher()
        let bogus = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        watcher.watch(url: bogus)
        // Should not crash — open() returns -1, guard exits early
        watcher.stop()
    }

    @Test func rapidChangesDebounce() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let tracker = CallbackTracker()
        let watcher = DirectoryWatcher()
        watcher.onChange = { Task { await tracker.increment() } }
        watcher.watch(url: dir)

        // Create 5 files rapidly — debounce (0.3s) should coalesce events
        for i in 0..<5 {
            _ = try TestHelpers.createFile("rapid-\(i).txt", in: dir)
        }

        try await Task.sleep(for: .seconds(2))
        let count = await tracker.callCount
        #expect(count >= 1, "Should have at least 1 callback")
        #expect(count < 5, "Debounce should collapse rapid changes, got \(count) callbacks")
        watcher.stop()
    }

    @Test func initWithOnChangeCallback() async throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let tracker = CallbackTracker()
        let watcher = DirectoryWatcher { Task { await tracker.increment() } }
        watcher.watch(url: dir)

        _ = try TestHelpers.createFile("init-cb.txt", in: dir)

        try await Task.sleep(for: .seconds(2))
        let wasCalled = await tracker.called
        #expect(wasCalled)
        watcher.stop()
    }
}
