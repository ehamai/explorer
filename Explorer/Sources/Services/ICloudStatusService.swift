import Foundation

/// Monitors iCloud Drive file download/upload status using NSMetadataQuery.
/// Publishes per-URL status updates that DirectoryViewModel can observe.
@MainActor
@Observable
final class ICloudStatusService {

    // MARK: - Properties

    /// Per-URL iCloud status, updated live by NSMetadataQuery.
    private(set) var statusMap: [URL: ICloudStatus] = [:]

    /// Whether iCloud Drive is available on this system.
    private(set) var isAvailable: Bool = false

    /// The iCloud Drive root URL, or nil if not signed in.
    private(set) var iCloudDriveURL: URL?

    private var metadataQuery: NSMetadataQuery?
    private var monitoredDirectory: URL?
    private var gatheringObserver: Any?
    private var updateObserver: Any?
    private var identityObserver: Any?

    // MARK: - Init

    init() {
        refreshAvailability()

        identityObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailability()
            }
        }
    }

    // MARK: - Public API

    /// Start monitoring a directory for iCloud status changes.
    func startMonitoring(directory: URL) {
        guard isInsideICloudDrive(directory) else {
            stopMonitoring()
            return
        }

        // Don't restart if already monitoring the same directory
        if monitoredDirectory == directory { return }
        stopMonitoring()
        monitoredDirectory = directory

        let query = NSMetadataQuery()
        query.searchScopes = [directory]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemPathKey)

        gatheringObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.processQueryResults(notification.object as? NSMetadataQuery)
            }
        }

        updateObserver = NotificationCenter.default.addObserver(
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

    /// Stop monitoring and clear status data.
    func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        monitoredDirectory = nil
        statusMap.removeAll()

        if let gatheringObserver {
            NotificationCenter.default.removeObserver(gatheringObserver)
        }
        if let updateObserver {
            NotificationCenter.default.removeObserver(updateObserver)
        }
        gatheringObserver = nil
        updateObserver = nil
    }

    /// Check if a URL is inside iCloud Drive (~/Library/Mobile Documents/).
    func isInsideICloudDrive(_ url: URL) -> Bool {
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents")
        return url.path.hasPrefix(mobileDocuments.path)
    }

    // MARK: - Private

    private func refreshAvailability() {
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents")
        if FileManager.default.fileExists(atPath: mobileDocuments.path) {
            isAvailable = true
            iCloudDriveURL = mobileDocuments
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
            newMap[url] = deriveStatus(from: item)
        }

        statusMap = newMap
    }

    private func deriveStatus(from item: NSMetadataItem) -> ICloudStatus {
        if let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String {
            if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                if let isUploading = item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool,
                   isUploading {
                    let progress = (item.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double ?? 0) / 100.0
                    return .uploading(progress: progress)
                }
                return .current
            } else if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
                if let isDownloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool,
                   isDownloading {
                    let progress = (item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0) / 100.0
                    return .downloading(progress: progress)
                }
                return .cloudOnly
            }
        }

        if let error = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError {
            return .error(error.localizedDescription)
        }
        if let error = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError {
            return .error(error.localizedDescription)
        }

        return .current
    }
}
