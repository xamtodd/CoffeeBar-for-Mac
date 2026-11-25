import AppKit
import ServiceManagement

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

/// Linksklick auf die Tasse: an/aus. Rechtsklick (oder ⌥/⌃-Klick): Menü mit allen Optionen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let assertion = AwakeAssertion()
    private let defaults = UserDefaults.standard

    // Manuell: an bis `manualUntil` (nil = unbegrenzt)
    private var manualOn = false
    private var manualUntil: Date?
    private var since: Date?

    private var claudeCount = 0
    private var batteryLowBlock = false
    private var tickTimer: Timer?
    private var claudeTimer: Timer?

    // Einstellungen
    private var claudeMode: Bool {
        get { defaults.object(forKey: "claudeMode") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "claudeMode"); checkClaude() }
    }
    private var keepDisplay: Bool {
        get { defaults.bool(forKey: "keepDisplay") }
        set { defaults.set(newValue, forKey: "keepDisplay"); apply() }
    }
    private var batteryGuard: Bool {
        get { defaults.object(forKey: "batteryGuard") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "batteryGuard"); apply() }
    }
    /// Standarddauer für Linksklick in Minuten (0 = unbegrenzt)
    private var defaultMinutes: Int {
        get { defaults.integer(forKey: "defaultMinutes") }
        set { defaults.set(newValue, forKey: "defaultMinutes") }
    }

    private let durations: [(String, Int)] = [
        ("15 Minuten", 15), ("30 Minuten", 30), ("1 Stunde", 60), ("2 Stunden", 120),
        ("4 Stunden", 240), ("8 Stunden", 480), ("Unbegrenzt", 0),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        claudeTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkClaude() }
        }
        checkClaude()
    }

    func applicationWillTerminate(_ notification: Notification) {
        assertion.set(active: false, display: false, reason: "")
    }

    // MARK: - Zustand

    private var claudeKeepsAwake: Bool { claudeMode && claudeCount > 0 }
    private var shouldBeAwake: Bool { (manualOn || claudeKeepsAwake) && !batteryLowBlock }

    private func apply() {
        if manualOn, let until = manualUntil, until <= Date() { turnOffManual() }

        if batteryGuard, let pct = Power.batteryPercentIfOnBattery(), pct < 20 {
            if !batteryLowBlock { batteryLowBlock = true; turnOffManual() }
        } else {
            batteryLowBlock = false
        }

        let awake = shouldBeAwake
        if awake && since == nil { since = Date() }
        if !awake { since = nil }
        assertion.set(active: awake, display: keepDisplay,
                      reason: claudeKeepsAwake && !manualOn ? "KaffeeBar: Claude Code läuft" : "KaffeeBar")
        updateButton()
    }

    private func checkClaude() {
        if claudeMode {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let n = ClaudeWatcher.runningCount()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.claudeCount = n; self?.apply() }
                }
            }
        } else {
            claudeCount = 0
            apply()
        }
    }

    private func turnOnManual(minutes: Int) {
        manualOn = true
        manualUntil = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil
        batteryLowBlock = false
        apply()
    }

    private func turnOffManual() {
        manualOn = false
        manualUntil = nil
    }

    // MARK: - Menüleiste

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let awake = assertion.isActive
        let name = awake ? "cup.and.saucer.fill" : "cup.and.saucer"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: awake ? "Wach" : "Aus")
        img?.isTemplate = true
        button.image = img
        button.appearsDisabled = !awake && batteryLowBlock

        if awake, manualOn, let until = manualUntil {
            button.title = " " + Self.short(until.timeIntervalSinceNow)
        } else {
            button.title = ""
        }
        button.toolTip = statusLine
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggle()
        }
    }

    @objc private func toggle() {
        if manualOn { turnOffManual(); apply() } else { turnOnManual(minutes: defaultMinutes) }
    }

    // MARK: - Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: manualOn ? "Ausschalten" : "Einschalten (\(label(for: defaultMinutes)))",
                                    action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let forItem = NSMenuItem(title: "Wach halten für", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, minutes) in durations {
            let it = NSMenuItem(title: title, action: #selector(pickDuration(_:)), keyEquivalent: "")
            it.target = self
            it.tag = minutes
            sub.addItem(it)
        }
        forItem.submenu = sub
        menu.addItem(forItem)

        menu.addItem(.separator())
        let claude = check("Solange Claude Code läuft", claudeMode, #selector(toggleClaudeMode))
        menu.addItem(claude)
        if claudeMode {
            let info = NSMenuItem(title: claudeCount == 0 ? "   Keine Claude-Sitzung aktiv"
                                    : "   \(claudeCount) Claude-Prozess\(claudeCount == 1 ? "" : "e") aktiv",
                                  action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(.separator())
        menu.addItem(check("Bildschirm anlassen", keepDisplay, #selector(toggleDisplay)))
        menu.addItem(check("Bei Akku unter 20 % ausschalten", batteryGuard, #selector(toggleBattery)))

        let defItem = NSMenuItem(title: "Linksklick schaltet ein für", action: nil, keyEquivalent: "")
        let defSub = NSMenu()
        for (title, minutes) in durations {
            let it = NSMenuItem(title: title, action: #selector(pickDefault(_:)), keyEquivalent: "")
            it.target = self
            it.tag = minutes
            it.state = minutes == defaultMinutes ? .on : .off
            defSub.addItem(it)
        }
        defItem.submenu = defSub
        menu.addItem(defItem)

        menu.addItem(check("Bei Anmeldung starten", SMAppService.mainApp.status == .enabled,
                           #selector(toggleLogin)))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "KaffeeBar beenden", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func check(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.state = on ? .on : .off
        return it
    }

    @objc private func pickDuration(_ sender: NSMenuItem) { turnOnManual(minutes: sender.tag) }
    @objc private func pickDefault(_ sender: NSMenuItem) { defaultMinutes = sender.tag }
    @objc private func toggleClaudeMode() { claudeMode.toggle() }
    @objc private func toggleDisplay() { keepDisplay.toggle() }
    @objc private func toggleBattery() { batteryGuard.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Texte

    private var statusLine: String {
        if batteryLowBlock { return "Aus – Akku unter 20 %" }
        guard assertion.isActive else { return "Aus – der Mac darf schlafen" }
        var parts: [String] = []
        if manualOn, let until = manualUntil {
            parts.append("Wach bis \(Self.clock.string(from: until)) · noch \(Self.long(until.timeIntervalSinceNow))")
        } else if manualOn {
            parts.append("Wach, unbegrenzt")
        } else {
            parts.append("Wach, solange Claude Code läuft")
        }
        if let since { parts.append("seit \(Self.clock.string(from: since))") }
        return parts.joined(separator: " · ")
    }

    private func label(for minutes: Int) -> String {
        durations.first { $0.1 == minutes }?.0 ?? "\(minutes) Min"
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "1:05" bzw. "12m" für die Menüleiste
    private static func short(_ t: TimeInterval) -> String {
        let m = max(0, Int((t / 60).rounded(.up)))
        return m >= 60 ? String(format: "%d:%02d", m / 60, m % 60) : "\(m)m"
    }

    private static func long(_ t: TimeInterval) -> String {
        let m = max(0, Int((t / 60).rounded(.up)))
        return m >= 60 ? "\(m / 60) Std \(m % 60) Min" : "\(m) Min"
    }
}
