import SwiftUI
import AppKit

extension Notification.Name {
    static let trackZoneToggleTracking = Notification.Name("trackZoneToggleTracking")
}

@main
struct RadialApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar icon + dropdown — no Dock icon (LSUIElement = YES in build settings).
        // No Window/Settings scene: settings window is managed entirely by AppDelegate.
        MenuBarExtra {
            MenuBarMenuView()
        } label: {
            Image(systemName: "hand.draw.fill")
                .imageScale(.medium)
        }
    }
}

// MARK: - Menu Bar Dropdown

private struct MenuBarMenuView: View {
    @State private var isTracking = true

    var body: some View {
        Button(isTracking ? "Pause Tracking" : "Resume Tracking") {
            isTracking.toggle()
            NotificationCenter.default.post(name: .trackZoneToggleTracking, object: nil)
        }

        Divider()

        Button("Settings…") {
            AppDelegate.shared?.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Radial") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    /// Lazily created settings window — recreated if closed and deallocated.
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Start trackpad monitoring immediately — no need to open settings first.
        SessionEngine.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func showSettings() {
        if settingsWindow == nil || !settingsWindow!.isVisible {
            let controller = NSHostingController(rootView: ContentView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Radial"
            window.setContentSize(NSSize(width: 820, height: 620))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.collectionBehavior = [.managed, .moveToActiveSpace]
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Restore collection behavior so window stops following the user.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.settingsWindow?.collectionBehavior = [.managed]
        }
    }
}

