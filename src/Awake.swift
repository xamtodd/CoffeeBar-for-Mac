import Foundation
import IOKit.pwr_mgt
import IOKit.ps

/// Hält den Mac über IOKit-Power-Assertions wach – dasselbe, was `caffeinate` intern macht,
/// nur ohne Kindprozess. Beendet sich die App, gibt macOS die Assertions automatisch frei.
final class AwakeAssertion {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0

    var isActive: Bool { systemID != 0 }
    var keepsDisplayOn: Bool { displayID != 0 }

    /// Setzt den gewünschten Zustand; doppelte Aufrufe sind harmlos.
    func set(active: Bool, display: Bool, reason: String) {
        if active {
            if systemID == 0 { systemID = Self.create("PreventUserIdleSystemSleep", reason) }
            if display, displayID == 0 { displayID = Self.create("PreventUserIdleDisplaySleep", reason) }
            if !display { Self.release(&displayID) }
        } else {
            Self.release(&systemID)
            Self.release(&displayID)
        }
    }

    private static func create(_ type: String, _ reason: String) -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        let r = IOPMAssertionCreateWithName(type as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            reason as CFString, &id)
        return r == kIOReturnSuccess ? id : 0
    }

    private static func release(_ id: inout IOPMAssertionID) {
        if id != 0 { IOPMAssertionRelease(id); id = 0 }
    }
}

enum Power {
    /// Akkustand in Prozent, nur wenn der Mac gerade am Akku läuft (sonst nil).
    static func batteryPercentIfOnBattery() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return cur * 100 / max
        }
        return nil
    }
}

enum ClaudeWatcher {
    /// Anzahl laufender Claude-Code-Prozesse (`claude` im Terminal).
    static func runningCount() -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", "claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return 0 }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline).count
    }
}
