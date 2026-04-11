import Testing
import Foundation
@testable import Explorer

@Suite("ICloudDriveService")
@MainActor
struct ICloudDriveServiceTests {

    // MARK: - Availability

    @Test func initDetectsICloudAvailability() {
        let service = ICloudDriveService()
        let cloudDocsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let expected = FileManager.default.fileExists(atPath: cloudDocsPath.path)
        #expect(service.isAvailable == expected)
    }

    @Test func cloudDocsURLSetWhenAvailable() {
        let service = ICloudDriveService()
        if service.isAvailable {
            #expect(service.cloudDocsURL != nil)
            #expect(service.cloudDocsURL?.lastPathComponent == "com~apple~CloudDocs")
        } else {
            #expect(service.cloudDocsURL == nil)
        }
    }

    // MARK: - Root Detection

    @Test func isICloudDriveRootForCloudDocs() {
        let service = ICloudDriveService()
        guard service.isAvailable, let cloudDocsURL = service.cloudDocsURL else { return }
        #expect(service.isICloudDriveRoot(cloudDocsURL))
    }

    @Test func isICloudDriveRootFalseForOtherURLs() {
        let service = ICloudDriveService()
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        #expect(!service.isICloudDriveRoot(homeURL))
        #expect(!service.isICloudDriveRoot(URL(fileURLWithPath: "/tmp")))
    }

    @Test func isICloudDriveRootFalseForSubfolders() {
        let service = ICloudDriveService()
        guard service.isAvailable, let cloudDocsURL = service.cloudDocsURL else { return }
        let subfolder = cloudDocsURL.appendingPathComponent("Documents")
        #expect(!service.isICloudDriveRoot(subfolder))
    }

    // MARK: - Merged Enumeration

    @Test func enumerateICloudDriveRootReturnsItems() {
        let service = ICloudDriveService()
        guard service.isAvailable else { return }

        let items = service.enumerateICloudDriveRoot(showHidden: false)
        // Should have at least some items (CloudDocs usually has Desktop, Documents)
        #expect(!items.isEmpty)
    }

    @Test func mergedEnumerationIncludesCloudDocsContents() {
        let service = ICloudDriveService()
        guard service.isAvailable else { return }

        let items = service.enumerateICloudDriveRoot(showHidden: false)
        let names = items.map(\.name)

        // CloudDocs should have at least Desktop or Documents
        let hasCommonFolder = names.contains("Desktop") || names.contains("Documents")
        #expect(hasCommonFolder, "Expected CloudDocs to contain Desktop or Documents")
    }

    @Test func mergedEnumerationIncludesAppFolders() {
        let service = ICloudDriveService()
        guard service.isAvailable else { return }

        let items = service.enumerateICloudDriveRoot(showHidden: false)
        let names = items.map(\.name)

        // If there are app containers, they should use localized names (not raw bundle IDs)
        for name in names {
            #expect(!name.contains("com~apple~"), "Found raw bundle ID in display: \(name)")
            #expect(!name.contains("iCloud~"), "Found raw iCloud container ID in display: \(name)")
        }
    }

    @Test func appFolderURLsPointToDocumentsSubfolder() {
        let service = ICloudDriveService()
        guard service.isAvailable else { return }

        let items = service.enumerateICloudDriveRoot(showHidden: false)

        // App folder items should have URLs ending in /Documents
        let mobileDocsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents").path

        for item in items where item.isDirectory {
            let parentPath = item.url.deletingLastPathComponent().path
            // If this item's parent is a container in Mobile Documents (not CloudDocs),
            // then the URL should end with /Documents
            if parentPath != service.cloudDocsURL?.path && parentPath.hasPrefix(mobileDocsPath) {
                #expect(item.url.lastPathComponent == "Documents",
                       "App folder \(item.name) URL should point to Documents/: \(item.url.path)")
            }
        }
    }

    @Test func mergedEnumerationAllItemsAreDirectoriesOrFiles() {
        let service = ICloudDriveService()
        guard service.isAvailable else { return }

        let items = service.enumerateICloudDriveRoot(showHidden: false)
        // Every item should be valid
        for item in items {
            #expect(!item.name.isEmpty, "Item should have a name")
            #expect(item.url.isFileURL, "Item URL should be a file URL")
        }
    }

    @Test func enumerateReturnsEmptyWhenUnavailable() {
        // If iCloud is not available, should return empty
        let service = ICloudDriveService()
        if !service.isAvailable {
            let items = service.enumerateICloudDriveRoot(showHidden: false)
            #expect(items.isEmpty)
        }
    }

    @Test func mobileDocsURLSetWhenAvailable() {
        let service = ICloudDriveService()
        if service.isAvailable {
            #expect(service.mobileDocsURL != nil)
            #expect(service.mobileDocsURL?.lastPathComponent == "Mobile Documents")
        } else {
            #expect(service.mobileDocsURL == nil)
        }
    }

    @Test func showHiddenFalseExcludesHiddenFiles() {
        let service = ICloudDriveService()
        guard service.isAvailable else { return }

        let visibleItems = service.enumerateICloudDriveRoot(showHidden: false)
        let allItems = service.enumerateICloudDriveRoot(showHidden: true)

        // Hidden items should not appear in visible-only enumeration
        let visibleNames = Set(visibleItems.map(\.name))
        for name in visibleNames {
            #expect(!name.hasPrefix("."), "Hidden file \(name) should not appear when showHidden=false")
        }

        // All items should be >= visible items
        #expect(allItems.count >= visibleItems.count)
    }

    @Test func isICloudDriveRootFalseForMobileDocuments() {
        let service = ICloudDriveService()
        guard service.isAvailable, let mobileDocsURL = service.mobileDocsURL else { return }
        // Mobile Documents itself is NOT the root — CloudDocs is
        #expect(!service.isICloudDriveRoot(mobileDocsURL))
    }

    @Test func appFolderItemsAreMarkedAsDirectories() {
        let service = ICloudDriveService()
        guard service.isAvailable else { return }

        let items = service.enumerateICloudDriveRoot(showHidden: false)
        let mobileDocsPath = service.mobileDocsURL?.path ?? ""

        // All app container folders should be directories
        for item in items where item.url.deletingLastPathComponent().path.hasPrefix(mobileDocsPath)
            && item.url.deletingLastPathComponent().path != service.cloudDocsURL?.path {
            #expect(item.isDirectory, "App folder \(item.name) should be a directory")
        }
    }
}
