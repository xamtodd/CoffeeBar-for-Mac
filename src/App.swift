import AppKit
import SwiftUI
import Combine

@main
enum Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Linksklick auf die Tasse: an/aus. Rechtsklick (oder ⌥/⌃-Klick): Panel mit allen Optionen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model = CoffeeModel()
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: CoffeePanel(model: model))

        cancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateButton() } }
        model.start()
        updateButton()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.releaseAll()
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let wantsPanel = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
            || event?.modifierFlags.contains(.control) == true
        if popover.isShown {
            popover.performClose(nil)
        } else if wantsPanel, let button = statusItem.button {
            model.refreshLogin()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        } else {
            model.toggle()
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let awake = model.awake
        let img = NSImage(systemSymbolName: awake ? "cup.and.saucer.fill" : "cup.and.saucer",
                          accessibilityDescription: awake ? "Wach" : "Aus")
        img?.isTemplate = true
        button.image = img
        button.appearsDisabled = !awake && model.batteryLow
        button.title = model.menuBarTimer.map { " " + $0 } ?? ""
        button.toolTip = model.statusLine
    }
}
