import Testing
import Foundation
@testable import Explorer

@Suite("NavigationViewModel")
struct NavigationViewModelTests {

    // MARK: - Init

    @Test func initSetsCurrentURL() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let vm = NavigationViewModel(startingURL: dir)
        #expect(vm.currentURL == dir.standardizedFileURL)
    }

    @Test func initDefaultsToHome() {
        let vm = NavigationViewModel()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        #expect(vm.currentURL == home)
    }

    // MARK: - navigate(to:)

    @Test func navigatePushesToBackStack() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        let original = vm.currentURL
        vm.navigate(to: sub)

        #expect(vm.backStack.count == 1)
        #expect(vm.backStack.first == original)
    }

    @Test func navigateClearsForwardStack() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub1 = try TestHelpers.createFolder("sub1", in: dir)
        let sub2 = try TestHelpers.createFolder("sub2", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        vm.navigate(to: sub1)
        vm.goBack()
        #expect(!vm.forwardStack.isEmpty)

        vm.navigate(to: sub2)
        #expect(vm.forwardStack.isEmpty)
    }

    @Test func navigateUpdatesCurrentURL() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        vm.navigate(to: sub)

        #expect(vm.currentURL.lastPathComponent == "sub")
    }

    @Test func navigateToSameURLIsNoOp() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        vm.navigate(to: sub)
        let urlAfterFirst = vm.currentURL
        let backCountBefore = vm.backStack.count

        // Navigate to the same resolved URL again
        vm.navigate(to: sub)
        #expect(vm.currentURL == urlAfterFirst)
        #expect(vm.backStack.count == backCountBefore)
    }

    // MARK: - goBack()

    @Test func goBackPopsBackStack() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        vm.navigate(to: sub)
        #expect(vm.backStack.count == 1)

        vm.goBack()
        #expect(vm.backStack.isEmpty)
    }

    @Test func goBackPushesToForwardStack() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        vm.navigate(to: sub)
        let navigatedURL = vm.currentURL

        vm.goBack()
        #expect(vm.forwardStack.count == 1)
        #expect(vm.forwardStack.first == navigatedURL)
    }

    @Test func goBackUpdatesCurrentURL() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        let original = vm.currentURL
        vm.navigate(to: sub)
        vm.goBack()

        #expect(vm.currentURL == original)
    }

    @Test func goBackWhenEmptyIsNoOp() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let vm = NavigationViewModel(startingURL: dir)
        let original = vm.currentURL

        vm.goBack()
        #expect(vm.currentURL == original)
        #expect(vm.backStack.isEmpty)
        #expect(vm.forwardStack.isEmpty)
    }

    // MARK: - goForward()

    @Test func goForwardPopsForwardStack() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        vm.navigate(to: sub)
        vm.goBack()
        #expect(vm.forwardStack.count == 1)

        vm.goForward()
        #expect(vm.forwardStack.isEmpty)
    }

    @Test func goForwardPushesToBackStack() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        let original = vm.currentURL
        vm.navigate(to: sub)
        vm.goBack()

        vm.goForward()
        #expect(vm.backStack.last == original)
    }

    @Test func goForwardUpdatesCurrentURL() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        vm.navigate(to: sub)
        let navigatedURL = vm.currentURL
        vm.goBack()

        vm.goForward()
        #expect(vm.currentURL == navigatedURL)
    }

    @Test func goForwardWhenEmptyIsNoOp() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let vm = NavigationViewModel(startingURL: dir)
        let original = vm.currentURL

        vm.goForward()
        #expect(vm.currentURL == original)
        #expect(vm.backStack.isEmpty)
        #expect(vm.forwardStack.isEmpty)
    }

    // MARK: - goUp()

    @Test func goUpNavigatesToParent() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("child", in: dir)

        let vm = NavigationViewModel(startingURL: sub)
        vm.goUp()

        #expect(vm.currentURL.lastPathComponent == dir.lastPathComponent)
    }

    @Test func goUpAtRootIsNoOp() {
        let vm = NavigationViewModel(startingURL: URL(fileURLWithPath: "/"))
        #expect(!vm.canGoUp)

        vm.goUp()
        #expect(vm.currentURL.path == "/")
        #expect(vm.backStack.isEmpty)
    }

    // MARK: - Computed properties

    @Test func canGoBackReflectsBackStack() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        #expect(!vm.canGoBack)

        vm.navigate(to: sub)
        #expect(vm.canGoBack)

        vm.goBack()
        #expect(!vm.canGoBack)
    }

    @Test func canGoForwardReflectsForwardStack() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("sub", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        #expect(!vm.canGoForward)

        vm.navigate(to: sub)
        #expect(!vm.canGoForward)

        vm.goBack()
        #expect(vm.canGoForward)

        vm.goForward()
        #expect(!vm.canGoForward)
    }

    @Test func canGoUpTrueForNonRoot() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }

        let vm = NavigationViewModel(startingURL: dir)
        #expect(vm.canGoUp)

        let rootVM = NavigationViewModel(startingURL: URL(fileURLWithPath: "/"))
        #expect(!rootVM.canGoUp)
    }

    @Test func pathComponentsFromRootToCurrentURL() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let child = try TestHelpers.createFolder("child", in: dir)

        let vm = NavigationViewModel(startingURL: child)
        let components = vm.pathComponents

        #expect(components.first?.name == "/")
        #expect(components.last?.name == "child")
        #expect(components.count >= 3) // at least /, some parent, child
    }

    // MARK: - navigateToPathComponent

    @Test func navigateToPathComponentDelegatesToNavigate() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub = try TestHelpers.createFolder("target", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        vm.navigateToPathComponent(url: sub)

        #expect(vm.currentURL.lastPathComponent == "target")
        #expect(vm.backStack.count == 1)
    }

    // MARK: - Complex scenario

    @Test func multipleNavigationsAndBackForward() throws {
        let dir = try TestHelpers.makeTempDir()
        defer { TestHelpers.cleanup(dir) }
        let sub1 = try TestHelpers.createFolder("sub1", in: dir)
        let sub2 = try TestHelpers.createFolder("sub2", in: dir)
        let sub3 = try TestHelpers.createFolder("sub3", in: dir)

        let vm = NavigationViewModel(startingURL: dir)
        let resolvedDir = vm.currentURL

        // Navigate: dir → sub1 → sub2 → sub3
        vm.navigate(to: sub1)
        let resolvedSub1 = vm.currentURL
        vm.navigate(to: sub2)
        let resolvedSub2 = vm.currentURL
        vm.navigate(to: sub3)
        let resolvedSub3 = vm.currentURL

        #expect(vm.backStack == [resolvedDir, resolvedSub1, resolvedSub2])
        #expect(vm.forwardStack.isEmpty)

        // Go back to sub2
        vm.goBack()
        #expect(vm.currentURL == resolvedSub2)
        #expect(vm.backStack == [resolvedDir, resolvedSub1])
        #expect(vm.forwardStack == [resolvedSub3])

        // Go forward to sub3
        vm.goForward()
        #expect(vm.currentURL == resolvedSub3)
        #expect(vm.backStack == [resolvedDir, resolvedSub1, resolvedSub2])
        #expect(vm.forwardStack.isEmpty)
    }
}
