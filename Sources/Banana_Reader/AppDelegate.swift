import AppKit

extension Notification.Name {
    static let bnnReaderDidReceiveOpenURLs = Notification.Name("bnnReaderDidReceiveOpenURLs")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        DispatchQueue.main.async {
            NSApp.windows.forEach(Self.configureResizable)
            self.handleLaunchArgumentsIfNeeded()
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        deliverOpenURLs([URL(fileURLWithPath: filename)])
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        let accepted = deliverOpenURLs(urls)
        sender.reply(toOpenOrPrint: accepted ? .success : .failure)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        _ = deliverOpenURLs(urls)
    }

    static func consumePendingOpenURLs() -> [URL] {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc
    private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        Self.configureResizable(window)
    }

    private static func configureResizable(_ window: NSWindow) {
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }

        if window.minSize.width > 760 || window.minSize.height > 520 {
            window.minSize = NSSize(width: 760, height: 520)
        }
    }

    private func handleLaunchArgumentsIfNeeded() {
        let potentialPaths = CommandLine.arguments.dropFirst()
        guard !potentialPaths.isEmpty else {
            return
        }

        let urls = potentialPaths.map { URL(fileURLWithPath: $0) }
        _ = deliverOpenURLs(urls)
    }

    @discardableResult
    private func deliverOpenURLs(_ urls: [URL]) -> Bool {
        let candidateFiles = urls.filter { url in
            guard url.isFileURL else {
                return false
            }

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }

        guard !candidateFiles.isEmpty else {
            return false
        }

        Self.pendingOpenURLs = candidateFiles
        NotificationCenter.default.post(name: .bnnReaderDidReceiveOpenURLs, object: candidateFiles)
        return true
    }
}
