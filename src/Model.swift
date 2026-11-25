import Foundation
import ServiceManagement

@MainActor
final class CoffeeModel: ObservableObject {
    // Manuell: an bis `manualUntil` (nil = unbegrenzt)
    @Published private(set) var manualOn = false
    @Published private(set) var manualStart: Date?
    @Published private(set) var manualUntil: Date?
    @Published private(set) var since: Date?
    @Published private(set) var awake = false
    @Published private(set) var claudeCount = 0
    @Published private(set) var batteryLow = false
    @Published private(set) var now = Date()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    // Einstellungen
    @Published var claudeMode: Bool = UserDefaults.standard.object(forKey: "claudeMode") as? Bool ?? true {
        didSet { UserDefaults.standard.set(claudeMode, forKey: "claudeMode"); checkClaude() }
    }
    @Published var keepDisplay: Bool = UserDefaults.standard.bool(forKey: "keepDisplay") {
        didSet { UserDefaults.standard.set(keepDisplay, forKey: "keepDisplay"); apply() }
    }
    @Published var batteryGuard: Bool = UserDefaults.standard.object(forKey: "batteryGuard") as? Bool ?? true {
        didSet { UserDefaults.standard.set(batteryGuard, forKey: "batteryGuard"); apply() }
    }
    /// Dauer für den Linksklick in Minuten (0 = unbegrenzt)
    @Published var defaultMinutes: Int = UserDefaults.standard.integer(forKey: "defaultMinutes") {
        didSet { UserDefaults.standard.set(defaultMinutes, forKey: "defaultMinutes") }
    }

    static let durations: [(short: String, long: String, minutes: Int)] = [
        ("15m", "15 Minuten", 15), ("30m", "30 Minuten", 30), ("1h", "1 Stunde", 60),
        ("2h", "2 Stunden", 120), ("4h", "4 Stunden", 240), ("8h", "8 Stunden", 480), ("∞", "Unbegrenzt", 0),
    ]

    private let assertion = AwakeAssertion()
    private var timers: [Timer] = []

    func start() {
        timers = [
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            },
            Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkClaude() }
            },
        ]
        checkClaude()
    }

    func releaseAll() { assertion.set(active: false, display: false, reason: "") }

    // MARK: - Aktionen

    func toggle() { manualOn ? turnOff() : turnOn(minutes: defaultMinutes) }

    func turnOn(minutes: Int) {
        manualOn = true
        manualStart = Date()
        manualUntil = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil
        batteryLow = false
        apply()
    }

    func turnOff() {
        clearManual()
        apply()
    }

    func refreshLogin() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        refreshLogin()
    }

    // MARK: - Zustand

    var claudeKeepsAwake: Bool { claudeMode && claudeCount > 0 }

    func apply() {
        now = Date()
        if manualOn, let until = manualUntil, until <= now { clearManual() }

        if batteryGuard, let pct = Power.batteryPercentIfOnBattery(), pct < 20 {
            if !batteryLow { batteryLow = true; clearManual() }
        } else {
            batteryLow = false
        }

        let shouldBeAwake = (manualOn || claudeKeepsAwake) && !batteryLow
        if shouldBeAwake && since == nil { since = now }
        if !shouldBeAwake { since = nil }
        assertion.set(active: shouldBeAwake, display: keepDisplay,
                      reason: claudeKeepsAwake && !manualOn ? "CoffeeBar: Claude Code läuft" : "CoffeeBar")
        awake = assertion.isActive
    }

    private func clearManual() {
        manualOn = false
        manualStart = nil
        manualUntil = nil
    }

    private func checkClaude() {
        guard claudeMode else { claudeCount = 0; apply(); return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let n = ClaudeWatcher.runningCount()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.claudeCount = n; self?.apply() }
            }
        }
    }

    // MARK: - Texte

    /// Anteil der abgelaufenen Zeit bei Timer (0…1), sonst nil
    var timerProgress: Double? {
        guard manualOn, let start = manualStart, let until = manualUntil else { return nil }
        let total = until.timeIntervalSince(start)
        return total > 0 ? min(1, max(0, now.timeIntervalSince(start) / total)) : nil
    }

    var remaining: TimeInterval? { manualOn ? manualUntil.map { $0.timeIntervalSince(now) } : nil }

    var menuBarTimer: String? {
        guard awake, let r = remaining else { return nil }
        let m = max(0, Int((r / 60).rounded(.up)))
        return m >= 60 ? String(format: "%d:%02d", m / 60, m % 60) : "\(m)m"
    }

    var headline: String {
        if batteryLow { return "Aus – Akku unter 20 %" }
        guard awake else { return "Aus" }
        if manualOn { return manualUntil == nil ? "Wach, unbegrenzt" : "Wach" }
        return "Wach, solange Claude läuft"
    }

    var statusLine: String {
        if batteryLow { return "Wird bei Akku unter 20 % automatisch ausgeschaltet" }
        guard awake else { return "Der Mac darf schlafen" }
        var parts: [String] = []
        if let until = manualUntil, manualOn {
            parts.append("bis \(Self.clock.string(from: until)) Uhr")
        }
        if let since { parts.append("seit \(Self.clock.string(from: since)) Uhr") }
        return parts.joined(separator: " · ")
    }

    var remainingText: String? {
        guard let r = remaining else { return nil }
        let m = max(0, Int((r / 60).rounded(.up)))
        return m >= 60 ? "noch \(m / 60) Std \(m % 60) Min" : "noch \(m) Min"
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
