import AppKit
import SwiftUI

@main
struct MacAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                controller: appDelegate.controller,
                quit: { NSApp.terminate(nil) }
            )
        } label: {
            Image(systemName: appDelegate.controller.isRunning ? "cup.and.saucer.fill" : "cup.and.saucer")
                .accessibilityLabel("MacAwake") // [VERIFY] confirm label matches intent
                .accessibilityValue(appDelegate.controller.isRunning ? "On" : "Off")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(controller: appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = CaffeinateController()
    private var rightClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard event.window == nil || event.window?.level == .statusBar else { return event }
            self?.controller.toggle()
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }
        controller.stop()
    }
}
