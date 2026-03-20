import Foundation

final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3
    private let queue = DispatchQueue(label: "com.explorer.directorywatcher", qos: .utility)

    var onChange: (() -> Void)?

    init(onChange: (() -> Void)? = nil) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func watch(url: URL) {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        fileDescriptor = fd

        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )

        dispatchSource.setEventHandler { [weak self] in
            self?.handleEvent()
        }

        dispatchSource.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source = dispatchSource
        dispatchSource.resume()
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let source = source {
            source.cancel()
            self.source = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func handleEvent() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let callback = self.onChange else { return }
            DispatchQueue.main.async {
                callback()
            }
        }

        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
