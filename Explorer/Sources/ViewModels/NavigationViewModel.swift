import Foundation
import SwiftUI

@Observable
final class NavigationViewModel {

    // MARK: - Properties

    private(set) var currentURL: URL
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []

    // MARK: - Computed Properties

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentURL.path != "/" }

    /// Breadcrumb path components from root to currentURL.
    /// e.g. /Users/ehamai/Documents →
    ///   [("/", /), ("Users", /Users), ("ehamai", /Users/ehamai), ("Documents", /Users/ehamai/Documents)]
    var pathComponents: [(name: String, url: URL)] {
        var components: [(name: String, url: URL)] = []
        var url = currentURL.standardizedFileURL

        // Collect components walking up to root
        var stack: [(String, URL)] = []
        while url.path != "/" {
            stack.append((url.lastPathComponent, url))
            url = url.deletingLastPathComponent().standardizedFileURL
        }
        // Root
        components.append((name: "/", url: URL(fileURLWithPath: "/")))
        // Reverse so we go from root downward
        for (name, segmentURL) in stack.reversed() {
            components.append((name: name, url: segmentURL))
        }
        return components
    }

    // MARK: - Init

    init(startingURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.currentURL = startingURL.standardizedFileURL
    }

    // MARK: - Navigation Methods

    /// Navigate to a new directory, pushing the current location onto the back stack.
    func navigate(to url: URL) {
        // Resolve the true on-disk path to fix casing on case-insensitive filesystems
        let resolved: URL
        if let realPath = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            resolved = URL(fileURLWithPath: realPath).standardizedFileURL
        } else if FileManager.default.fileExists(atPath: url.path) {
            // Use NSString's resolvingSymlinksInPath which also canonicalizes casing
            let canonical = (url.path as NSString).resolvingSymlinksInPath
            resolved = URL(fileURLWithPath: canonical).standardizedFileURL
        } else {
            resolved = url.standardizedFileURL
        }
        guard resolved != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = resolved
    }

    /// Go back to the previous location.
    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        currentURL = previous
    }

    /// Go forward to the next location.
    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        currentURL = next
    }

    /// Navigate up to the parent directory.
    func goUp() {
        guard canGoUp else { return }
        let parent = currentURL.deletingLastPathComponent().standardizedFileURL
        navigate(to: parent)
    }

    /// Navigate directly to a breadcrumb path component.
    func navigateToPathComponent(url: URL) {
        let standardized = url.standardizedFileURL
        guard standardized != currentURL else { return }
        navigate(to: standardized)
    }
}
