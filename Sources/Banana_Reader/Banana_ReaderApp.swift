import SwiftUI

@main
struct BananaReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Banana Reader") {
            ContentView()
                .tint(Color(red: 0.941, green: 0.525, blue: 0.290))
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // Replace the default "New" item with "Open…", since this is a
            // read-only viewer.
            CommandGroup(replacing: .newItem) {
                Button("打开…") {
                    NotificationCenter.default.post(name: .bnnReaderRequestOpen, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("放大") {
                    NotificationCenter.default.post(
                        name: .bnnReaderRequestZoom,
                        object: Double(ZoomConstants.step)
                    )
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("缩小") {
                    NotificationCenter.default.post(
                        name: .bnnReaderRequestZoom,
                        object: Double(-ZoomConstants.step)
                    )
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("实际大小") {
                    NotificationCenter.default.post(
                        name: .bnnReaderRequestZoom,
                        object: nil
                    )
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
