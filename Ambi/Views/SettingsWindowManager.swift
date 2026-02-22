import SwiftUI
import AppKit

@MainActor
class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var windowController: NSWindowController?

    private init() {}

    func open(appState: AppState) {
        // If window already exists and is visible, just bring it front
        if let wc = windowController, let window = wc.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        let wc = NSWindowController(window: window)
        wc.showWindow(nil)
        windowController = wc

        NSApp.activate(ignoringOtherApps: true)
    }
}
