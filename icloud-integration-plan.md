# iCloud Drive Integration Plan

## Executive Summary

**Yes, iCloud Drive integration is feasible.** Three competing approaches were evaluated:

| Approach | Scope | New Files | Modified Files | Complexity |
|----------|-------|-----------|----------------|------------|
| **A. Browse iCloud Drive as Location** ✅ | Browse existing iCloud Drive with real-time status | 3 | 10 | Medium |
| B. Full iCloud via Custom Container | Custom ubiquity container + conflict resolution | 10 | 9 | High |
| C. Lightweight iCloud Awareness | Read-only URL resource keys, no real-time updates | 2 | 7 | Low |

### Why Plan A Wins

- **Plan C is too minimal** — URLResourceKey reads are point-in-time snapshots; no live sync progress. DirectoryWatcher (DispatchSource) doesn't catch iCloud sync state transitions reliably. Users won't see files appearing as they download.
- **Plan B is overengineered** — A custom ubiquity container means the app manages its own iCloud storage, not browsing the user's existing iCloud Drive. Conflict resolution UI and NSFilePresenter add weeks of work for edge cases most users won't hit. Requires Apple Developer provisioning profile changes.
- **Plan A is the Goldilocks zone** — Browse the user's *existing* iCloud Drive (`~/Library/Mobile Documents/`). NSMetadataQuery provides live download/upload status. NSFileCoordinator ensures safe file operations. No custom container needed. Graceful degradation when iCloud is unavailable.

---

## Approach

Treat iCloud Drive as just another browsable location in the sidebar. The local mirror at `~/Library/Mobile Documents/` is a real directory on disk — the iCloud daemon manages syncing. We layer on top with:

1. **ICloudStatusService** (new actor) — wraps `NSMetadataQuery` to monitor per-file download/upload status in real time
2. **ICloudStatus enum** (new model) — represents sync states: local, current, downloadable, downloading, uploading, error
3. **FileItem extension** — adds `iCloudStatus` property + handles `.icloud` placeholder files
4. **FileSystemService extension** — adds `startDownloading()`, `evictItem()`, and `NSFileCoordinator`-wrapped operations for iCloud paths
5. **View layer** — status badges in list/grid/mosaic views, context menu download/evict actions
6. **Sidebar** — "iCloud Drive" entry using `FileManager.url(forUbiquityContainerIdentifier: nil)`

### Key Design Decisions

- **No custom ubiquity container** — we browse the user's existing iCloud Drive, like Finder does
- **NSMetadataQuery for live status** — not polling URLResourceKeys (which go stale)
- **NSFileCoordinator only for iCloud paths** — local file operations keep their current fast path (zero overhead for non-iCloud files)
- **`.icloud` placeholder handling** — cloud-only files appear as `.MyFile.txt.icloud` on disk; we strip the prefix/suffix for display and show a cloud badge
- **Graceful degradation** — if `url(forUbiquityContainerIdentifier: nil)` returns `nil`, the sidebar entry simply doesn't appear

---

## Phase 1: Model + Service Foundation

### 1.1 NEW: `Explorer/Sources/Models/ICloudStatus.swift`

**Complexity: Low (~50 lines)**

```swift
import Foundation

/// Represents iCloud sync status for a file.
enum ICloudStatus: Equatable, Hashable {
    case local                          // Not in iCloud Drive
    case current                        // Downloaded and up-to-date
    case downloadable                   // Cloud-only placeholder (.icloud stub)
    case downloading(progress: Double)  // 0.0–1.0
    case uploading(progress: Double)    // 0.0–1.0
    case error(String)                  // Sync error

    var symbolName: String? {
        switch self {
        case .local:        return nil
        case .current:      return "checkmark.icloud"
        case .downloadable: return "icloud.and.arrow.down"
        case .downloading:  return "arrow.down.circle"
        case .uploading:    return "arrow.up.circle"
        case .error:        return "exclamationmark.icloud"
        }
    }

    var label: String {
        switch self {
        case .local:                    return ""
        case .current:                  return "Downloaded"
        case .downloadable:             return "In iCloud"
        case .downloading(let p):       return "Downloading \(Int(p * 100))%"
        case .uploading(let p):         return "Uploading \(Int(p * 100))%"
        case .error(let msg):           return "Error: \(msg)"
        }
    }

    var isAvailableLocally: Bool {
        switch self {
        case .local, .current, .uploading: return true
        default: return false
        }
    }

    var canDownload: Bool { self == .downloadable }

    var canEvict: Bool {
        if case .current = self { return true }
        return false
    }
}
```

### 1.2 MODIFY: `Explorer/Sources/Models/FileItem.swift`

**Complexity: Medium (~30 lines changed)**

Changes:
- Add `var iCloudStatus: ICloudStatus = .local` stored property
- Add `iCloudStatus` parameter to `init` (with default `.local`)
- Handle `.icloud` placeholder files in `fromURL(_:)`
- Add ubiquity resource keys to the prefetch set

```swift
// Add to resourceKeys:
.ubiquitousItemDownloadingStatusKey,
.ubiquitousItemIsDownloadingKey,
.ubiquitousItemIsUploadedKey,
.ubiquitousItemIsUploadingKey

// In fromURL(_:), handle .icloud placeholders:
let fileName = url.lastPathComponent
var resolvedURL = url
var iCloudStatus: ICloudStatus = .local

if fileName.hasPrefix(".") && fileName.hasSuffix(".icloud") {
    // ".MyFile.txt.icloud" → "MyFile.txt"
    let realName = String(fileName.dropFirst().dropLast(7))
    resolvedURL = url.deletingLastPathComponent().appendingPathComponent(realName)
    iCloudStatus = .downloadable
}

// Read ubiquity keys for non-placeholder files:
if iCloudStatus == .local {
    if let downloadingStatus = values.ubiquitousItemDownloadingStatus {
        if values.ubiquitousItemIsDownloading == true {
            iCloudStatus = .downloading(progress: 0)
        } else if downloadingStatus == .current {
            iCloudStatus = .current
        } else {
            iCloudStatus = .downloadable
        }
    }
}
```

### 1.3 NEW: `Explorer/Sources/Services/ICloudStatusService.swift`

**Complexity: High (~180 lines)**

An `@MainActor @Observable` service wrapping `NSMetadataQuery` to monitor iCloud file status in real time.

```swift
import Foundation

@MainActor @Observable
final class ICloudStatusService {
    /// Per-URL iCloud status, updated by NSMetadataQuery
    private(set) var statusMap: [URL: ICloudStatus] = [:]

    /// Whether iCloud Drive is available
    private(set) var isAvailable: Bool = false

    /// The iCloud Drive root URL (nil if not signed in)
    private(set) var iCloudDriveURL: URL?

    private var metadataQuery: NSMetadataQuery?
    private var monitoredDirectory: URL?

    init() {
        // Check iCloud availability
        if let url = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            isAvailable = true
            iCloudDriveURL = url
        }

        // Listen for iCloud account changes
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailability()
            }
        }
    }

    /// Start monitoring a directory for iCloud status changes
    func startMonitoring(directory: URL) {
        stopMonitoring()
        monitoredDirectory = directory

        // Only monitor if directory is inside iCloud Drive
        guard isInsideICloudDrive(directory) else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [directory]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemPathKey)

        // Observe updates
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.processQueryResults(notification.object as? NSMetadataQuery)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.processQueryResults(notification.object as? NSMetadataQuery)
            }
        }

        query.start()
        metadataQuery = query
    }

    func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        statusMap.removeAll()
    }

    /// Check if a URL is inside iCloud Drive
    func isInsideICloudDrive(_ url: URL) -> Bool {
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents")
        return url.path.hasPrefix(mobileDocuments.path)
    }

    // MARK: - Private

    private func refreshAvailability() {
        if let url = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            isAvailable = true
            iCloudDriveURL = url
        } else {
            isAvailable = false
            iCloudDriveURL = nil
            stopMonitoring()
        }
    }

    private func processQueryResults(_ query: NSMetadataQuery?) {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        var newMap: [URL: ICloudStatus] = [:]

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)

            let status = deriveStatus(from: item)
            newMap[url] = status
        }

        statusMap = newMap
    }

    private func deriveStatus(from item: NSMetadataItem) -> ICloudStatus {
        // Check download status
        if let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String {
            if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                return .current
            } else if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
                // Check if actively downloading
                if let isDownloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool,
                   isDownloading {
                    let progress = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0
                    return .downloading(progress: progress / 100.0)
                }
                return .downloadable
            }
        }

        // Check upload status
        if let isUploading = item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool,
           isUploading {
            let progress = item.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double ?? 0
            return .uploading(progress: progress / 100.0)
        }

        // Check for errors
        if let error = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError {
            return .error(error.localizedDescription)
        }
        if let error = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError {
            return .error(error.localizedDescription)
        }

        return .current
    }
}
```

### 1.4 MODIFY: `Explorer/Sources/Services/FileSystemService.swift`

**Complexity: Medium (~40 lines added)**

Add iCloud-specific file operations and NSFileCoordinator wrapper for iCloud paths.

```swift
// New methods:

func startDownloading(url: URL) throws {
    try FileManager.default.startDownloadingUbiquitousItem(at: url)
}

func evictItem(url: URL) throws {
    try FileManager.default.evictUbiquitousItem(at: url)
}

/// Coordinated file move for iCloud-synced files.
/// Falls back to regular moveItem for non-iCloud paths.
func coordinatedMove(from source: URL, to destination: URL) async throws {
    let coordinator = NSFileCoordinator()
    var coordinatorError: NSError?

    coordinator.coordinate(
        writingItemAt: source, options: .forMoving,
        writingItemAt: destination, options: .forReplacing,
        error: &coordinatorError
    ) { newSource, newDest in
        do {
            try FileManager.default.moveItem(at: newSource, to: newDest)
        } catch {
            // Error is captured by coordinator
        }
    }

    if let error = coordinatorError {
        throw error
    }
}

/// Coordinated file copy for iCloud-synced files.
func coordinatedCopy(from source: URL, to destination: URL) async throws {
    let coordinator = NSFileCoordinator()
    var coordinatorError: NSError?

    coordinator.coordinate(
        readingItemAt: source, options: [],
        writingItemAt: destination, options: .forReplacing,
        error: &coordinatorError
    ) { newSource, newDest in
        do {
            try FileManager.default.copyItem(at: newSource, to: newDest)
        } catch {
            // Error captured by coordinator
        }
    }

    if let error = coordinatorError {
        throw error
    }
}
```

### 1.5 MODIFY: `Explorer/Resources/Explorer.entitlements`

**Complexity: Low**

Add empty iCloud container identifiers to enable `url(forUbiquityContainerIdentifier: nil)`.

```xml
<!-- Add to existing entitlements dict: -->
<key>com.apple.developer.icloud-container-identifiers</key>
<array/>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array/>
```

**Note**: These empty arrays tell the system "use the default iCloud containers" (i.e., the user's iCloud Drive). No custom container is created. If the app is not codesigned with an iCloud-enabled provisioning profile, `url(forUbiquityContainerIdentifier: nil)` simply returns `nil` and the feature is hidden.

---

## Phase 2: ViewModel + Sidebar Integration

### 2.1 MODIFY: `Explorer/Sources/ViewModels/SidebarViewModel.swift`

**Complexity: Low (~15 lines)**

Add "iCloud Drive" to system locations, conditionally.

```swift
// In systemLocations computed property, after "Documents":
let iCloudDriveURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Mobile Documents")
if FileManager.default.fileExists(atPath: iCloudDriveURL.path) {
    locations.insert(
        SidebarLocation(name: "iCloud Drive", url: iCloudDriveURL, icon: "icloud.fill"),
        at: 2  // After Documents
    )
}
```

### 2.2 MODIFY: `Explorer/Sources/ViewModels/DirectoryViewModel.swift`

**Complexity: Medium (~30 lines)**

Integrate ICloudStatusService to update file items with live status.

```swift
// Add dependency:
private var iCloudStatusService: ICloudStatusService?

// In loadDirectory(url:), after loading items:
// Start iCloud monitoring if in iCloud Drive
if let service = iCloudStatusService, service.isInsideICloudDrive(url) {
    service.startMonitoring(directory: url)
}

// New methods:
func downloadItem(at url: URL) async {
    do {
        try await fileSystemService.startDownloading(url: url)
        await reloadCurrentDirectory()
    } catch {
        // Matches existing silent-catch pattern
    }
}

func evictItem(at url: URL) async {
    do {
        try await fileSystemService.evictItem(url: url)
        await reloadCurrentDirectory()
    } catch {
        // Silent catch
    }
}

/// Merge live iCloud status from NSMetadataQuery into items
func updateICloudStatus(from statusMap: [URL: ICloudStatus]) {
    for i in items.indices {
        if let status = statusMap[items[i].url] {
            items[i].iCloudStatus = status
        }
    }
}
```

### 2.3 MODIFY: `Explorer/Sources/ExplorerApp.swift`

**Complexity: Low (~5 lines)**

Wire up `ICloudStatusService` as an environment object.

```swift
@State private var iCloudStatusService = ICloudStatusService()

// In body, add to environment chain:
.environment(iCloudStatusService)
```

---

## Phase 3: View Layer

### 3.1 NEW: `Explorer/Sources/Views/Components/ICloudStatusBadge.swift`

**Complexity: Low (~35 lines)**

```swift
import SwiftUI

struct ICloudStatusBadge: View {
    let status: ICloudStatus

    var body: some View {
        if let symbolName = status.symbolName {
            Group {
                switch status {
                case .downloading(let progress), .uploading(let progress):
                    ZStack {
                        CircularProgressView(progress: progress)
                            .frame(width: 12, height: 12)
                        Image(systemName: symbolName)
                            .font(.system(size: 7))
                    }
                default:
                    Image(systemName: symbolName)
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(color)
            .help(status.label)
        }
    }

    private var color: Color {
        switch status {
        case .current:      return .green
        case .downloadable: return .secondary
        case .downloading:  return .blue
        case .uploading:    return .orange
        case .error:        return .red
        case .local:        return .clear
        }
    }
}
```

### 3.2 MODIFY: `Explorer/Sources/Views/Content/FileListView.swift`

**Complexity: Medium (~20 lines)**

- Add `ICloudStatusBadge` in the Name column after the file name
- Add iCloud context menu items (Download Now / Remove Download)

```swift
// In Name column HStack:
ICloudStatusBadge(status: item.iCloudStatus)

// In context menu:
if item.iCloudStatus.canDownload {
    Button("Download Now") {
        Task { await directoryVM.downloadItem(at: item.url) }
    }
}
if item.iCloudStatus.canEvict {
    Button("Remove Download") {
        Task { await directoryVM.evictItem(at: item.url) }
    }
}
```

### 3.3 MODIFY: `Explorer/Sources/Views/Content/IconGridView.swift`

**Complexity: Low (~15 lines)**

Same pattern as FileListView — badge overlay on icon, context menu items.

```swift
// Badge overlay on file icon:
.overlay(alignment: .bottomTrailing) {
    ICloudStatusBadge(status: item.iCloudStatus)
}
```

### 3.4 MODIFY: `Explorer/Sources/Views/Content/MosaicView.swift`

**Complexity: Low (~10 lines)**

Badge overlay on mosaic tiles + context menu items.

### 3.5 MODIFY: `Explorer/Sources/Views/Components/InspectorView.swift` (if exists)

**Complexity: Low (~10 lines)**

Show iCloud status in the file properties inspector panel.

```swift
if item.iCloudStatus != .local {
    LabeledContent("iCloud Status", value: item.iCloudStatus.label)
}
```

---

## Phase 4: Testing

### 4.1 NEW: `Explorer/Tests/ICloudStatusTests.swift`

**Complexity: Low (~40 lines)**

```swift
import Testing
@testable import Explorer

@Suite("ICloudStatus")
struct ICloudStatusTests {
    @Test func localHasNoSymbol() {
        #expect(ICloudStatus.local.symbolName == nil)
        #expect(ICloudStatus.local.label == "")
    }

    @Test func downloadableCanDownload() {
        #expect(ICloudStatus.downloadable.canDownload)
        #expect(!ICloudStatus.downloadable.canEvict)
        #expect(!ICloudStatus.downloadable.isAvailableLocally)
    }

    @Test func currentCanEvict() {
        #expect(ICloudStatus.current.canEvict)
        #expect(!ICloudStatus.current.canDownload)
        #expect(ICloudStatus.current.isAvailableLocally)
    }

    @Test func downloadingShowsProgress() {
        let status = ICloudStatus.downloading(progress: 0.5)
        #expect(status.label.contains("50%"))
        #expect(status.symbolName != nil)
        #expect(!status.isAvailableLocally)
    }

    @Test func uploadingShowsProgress() {
        let status = ICloudStatus.uploading(progress: 0.75)
        #expect(status.label.contains("75%"))
        #expect(status.isAvailableLocally)
    }

    @Test func errorShowsMessage() {
        let status = ICloudStatus.error("Disk full")
        #expect(status.label.contains("Disk full"))
    }

    @Test func allNonLocalCasesHaveSymbols() {
        let cases: [ICloudStatus] = [.current, .downloadable, .downloading(progress: 0), .uploading(progress: 0), .error("x")]
        for status in cases {
            #expect(status.symbolName != nil, "Missing symbol for \(status)")
        }
    }
}
```

### 4.2 MODIFY: `Explorer/Tests/FileItemTests.swift`

```swift
@Test func fromURLDefaultsToLocalICloudStatus() {
    let file = createFile(in: tempDir, name: "test.txt")
    let item = FileItem.fromURL(file)!
    #expect(item.iCloudStatus == .local)
}

@Test func iCloudPlaceholderDetection() {
    // Create a file named ".test.txt.icloud" to simulate a placeholder
    let placeholder = createFile(in: tempDir, name: ".test.txt.icloud")
    let item = FileItem.fromURL(placeholder)!
    #expect(item.name == "test.txt")
    #expect(item.iCloudStatus == .downloadable)
}
```

### 4.3 MODIFY: `Explorer/Tests/FileSystemServiceTests.swift`

```swift
@Test func startDownloadingNonUbiquitousItemThrows() async {
    let service = FileSystemService()
    let file = createFile(in: tempDir, name: "local.txt")
    do {
        try await service.startDownloading(url: file)
        Issue.record("Expected error for non-ubiquitous item")
    } catch {
        // Expected
    }
}

@Test func evictNonUbiquitousItemThrows() async {
    let service = FileSystemService()
    let file = createFile(in: tempDir, name: "local.txt")
    do {
        try await service.evictItem(url: file)
        Issue.record("Expected error for non-ubiquitous item")
    } catch {
        // Expected
    }
}
```

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Sandbox blocks `~/Library/Mobile Documents/`** | Medium | `url(forUbiquityContainerIdentifier: nil)` is the sanctioned API; it works in sandboxed apps. Fallback: sidebar entry hidden if nil returned. |
| **Entitlements require provisioning profile** | Medium | Empty iCloud container arrays may require an iCloud-enabled provisioning profile. If using ad-hoc signing, the feature degrades gracefully (returns nil). |
| **NSMetadataQuery lifecycle complexity** | Medium | Service encapsulates all query lifecycle; start/stop tied to directory navigation. |
| **`.icloud` placeholder edge cases** | Low | Well-documented pattern; Finder handles the same stubs. Test with real iCloud files. |
| **NSFileCoordinator deadlocks** | Low | Only used for iCloud paths. Coordinated ops run on actor's serial queue — no nesting. |
| **Stale status between query updates** | Low | NSMetadataQuery fires on every iCloud daemon state change. Debounce is built into the query API. |
| **Performance: 4 extra URLResourceKeys** | Low | Prefetched in the same `getattr` syscall batch. Negligible overhead. |
| **Breaking existing tests** | Low | New `iCloudStatus` has default value `.local`. `TestHelpers.makeFileItem()` may need one param added with default. |

---

## Summary

| File | Action | Complexity | Est. Lines |
|------|--------|-----------|-----------|
| `Models/ICloudStatus.swift` | **Create** | Low | ~50 |
| `Models/FileItem.swift` | Modify | Medium | ~30 |
| `Services/ICloudStatusService.swift` | **Create** | High | ~180 |
| `Services/FileSystemService.swift` | Modify | Medium | ~40 |
| `Resources/Explorer.entitlements` | Modify | Low | ~6 |
| `ViewModels/SidebarViewModel.swift` | Modify | Low | ~15 |
| `ViewModels/DirectoryViewModel.swift` | Modify | Medium | ~30 |
| `ExplorerApp.swift` | Modify | Low | ~5 |
| `Views/Components/ICloudStatusBadge.swift` | **Create** | Low | ~35 |
| `Views/Content/FileListView.swift` | Modify | Medium | ~20 |
| `Views/Content/IconGridView.swift` | Modify | Low | ~15 |
| `Views/Content/MosaicView.swift` | Modify | Low | ~10 |
| `Tests/ICloudStatusTests.swift` | **Create** | Low | ~40 |
| `Tests/FileItemTests.swift` | Modify | Low | ~15 |
| `Tests/FileSystemServiceTests.swift` | Modify | Low | ~15 |
| PLAN.md files (6 files) | Modify | Low | ~40 |
| **Total** | **4 new + 12 modified** | | **~545 lines** |

---

## Implementation Order

1. **Phase 1** (Foundation): `ICloudStatus` model → `FileItem` changes → `FileSystemService` methods → `ICloudStatusService` → Entitlements
2. **Phase 2** (Integration): `SidebarViewModel` → `DirectoryViewModel` → `ExplorerApp` wiring
3. **Phase 3** (UI): `ICloudStatusBadge` → FileListView → IconGridView → MosaicView → InspectorView
4. **Phase 4** (Testing): All test files + manual testing with real iCloud account

Phases 1-2 can be built and tested without UI changes. Phase 3 is all view-layer additions. Phase 4 validates everything end-to-end.

---

## Manual Testing Checklist

- [ ] Sign into iCloud on the Mac
- [ ] Open Explorer → verify "iCloud Drive" appears in sidebar
- [ ] Navigate to iCloud Drive → verify file listing works
- [ ] Cloud-only files show cloud badge (↓ icon)
- [ ] Right-click cloud-only file → "Download Now" → file downloads, badge updates to ✓
- [ ] Right-click downloaded file → "Remove Download" → file evicted, badge updates to ↓
- [ ] Copy a file into iCloud Drive → upload progress badge appears
- [ ] Sign out of iCloud → "iCloud Drive" disappears from sidebar
- [ ] Navigate to a local (non-iCloud) directory → no badges, no errors
- [ ] `.icloud` placeholder files display with clean names (no `.` prefix or `.icloud` suffix)

---

## Future Enhancements (Out of Scope)

- **Conflict resolution UI** — NSFileVersion-based version picker for sync conflicts
- **Batch download/evict** — Select multiple files and download/evict all at once
- **Storage quota display** — Show iCloud storage usage in status bar
- **Shared iCloud folders** — Display sharing indicators for collaborative folders
- **NSFilePresenter** — Register as file presenter for tighter integration with coordinated writes

---

## Revision: Merged iCloud Drive View (Implemented)

### Problem
The initial implementation pointed the sidebar at `~/Library/Mobile Documents/`, which shows raw container folder names (`com~apple~CloudDocs`, `com~apple~Pages`, etc.) instead of the user-friendly view Finder shows.

### Root Cause
Finder's "iCloud Drive" is a **virtual merged view**:
- User files come from `~/Library/Mobile Documents/com~apple~CloudDocs/`
- App-specific folders come from sibling container directories with `Documents/` subfolders
- Display names use `URLResourceKey.localizedNameKey` (e.g., `com~apple~Pages` → "Pages")

### Fix
Added `ICloudDriveService` (`Explorer/Sources/Services/ICloudDriveService.swift`) that:
1. Enumerates `com~apple~CloudDocs/` for user files
2. Scans sibling containers for app folders with `Documents/` subfolders
3. Uses `localizedNameKey` for friendly display names
4. Returns merged `[FileItem]` list matching Finder's view

**Sidebar** now points at `com~apple~CloudDocs` (which has `localizedName` = "iCloud Drive").

**DirectoryViewModel** detects the iCloud Drive root in `loadDirectory()` and branches to merged enumeration. Once navigating into any subfolder, standard filesystem enumeration takes over.

**FileItem.fromURL()** now reads `localizedNameKey` and uses it as the display name when available, so all file/folder names appear correctly throughout the app.
