import Testing
import Foundation
@testable import Explorer

@Suite("ICloudStatusService")
@MainActor
struct ICloudStatusServiceTests {

    // MARK: - Initialization

    @Test func initDetectsAvailability() {
        let service = ICloudStatusService()
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents")
        let expected = FileManager.default.fileExists(atPath: mobileDocuments.path)
        #expect(service.isAvailable == expected)
    }

    @Test func iCloudDriveURLSetWhenAvailable() {
        let service = ICloudStatusService()
        if service.isAvailable {
            #expect(service.iCloudDriveURL != nil)
        } else {
            #expect(service.iCloudDriveURL == nil)
        }
    }

    @Test func statusMapStartsEmpty() {
        let service = ICloudStatusService()
        #expect(service.statusMap.isEmpty)
    }

    // MARK: - isInsideICloudDrive

    @Test func iCloudDrivePathIsInsideICloudDrive() {
        let service = ICloudStatusService()
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        #expect(service.isInsideICloudDrive(mobileDocuments))
    }

    @Test func mobileDocumentsIsInsideICloudDrive() {
        let service = ICloudStatusService()
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents")
        #expect(service.isInsideICloudDrive(mobileDocuments))
    }

    @Test func subfolderOfMobileDocumentsIsInsideICloudDrive() {
        let service = ICloudStatusService()
        let subfolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Documents")
        #expect(service.isInsideICloudDrive(subfolder))
    }

    @Test func homeDirectoryIsNotInsideICloudDrive() {
        let service = ICloudStatusService()
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(!service.isInsideICloudDrive(home))
    }

    @Test func tmpIsNotInsideICloudDrive() {
        let service = ICloudStatusService()
        #expect(!service.isInsideICloudDrive(URL(fileURLWithPath: "/tmp")))
    }

    @Test func desktopIsNotInsideICloudDrive() {
        let service = ICloudStatusService()
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        #expect(!service.isInsideICloudDrive(desktop))
    }

    // MARK: - Monitoring Lifecycle

    @Test func startMonitoringNonICloudDirectoryStopsMonitoring() {
        let service = ICloudStatusService()
        // Starting monitoring on a non-iCloud directory should not crash
        // and should stop any existing monitoring
        service.startMonitoring(directory: URL(fileURLWithPath: "/tmp"))
        #expect(service.statusMap.isEmpty)
    }

    @Test func stopMonitoringClearsStatusMap() {
        let service = ICloudStatusService()
        service.stopMonitoring()
        #expect(service.statusMap.isEmpty)
    }

    @Test func stopMonitoringIsIdempotent() {
        let service = ICloudStatusService()
        service.stopMonitoring()
        service.stopMonitoring()
        #expect(service.statusMap.isEmpty)
    }
}
