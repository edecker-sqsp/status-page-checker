import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settings: Settings!
    private var monitor: StatusMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings()
        let monitor = StatusMonitor(settings: settings)
        self.settings = settings
        self.monitor = monitor

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = Health.operational.emoji
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let root = RootView(settings: settings, monitor: monitor)
            .frame(width: 380, height: 480)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = NSHostingController(rootView: root)

        // The menu bar emoji is driven from here rather than through
        // SwiftUI/Observation, since NSStatusItem is plain AppKit.
        monitor.onChange = { [weak self] in
            self?.statusItem.button?.title = self?.monitor.aggregateHealth.emoji ?? Health.unknown.emoji
        }

        monitor.start()
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
