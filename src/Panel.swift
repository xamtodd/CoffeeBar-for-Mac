import SwiftUI
import AppKit

extension Color {
    static let coffee = Color(red: 0.78, green: 0.52, blue: 0.30)
    static let coffeeDark = Color(red: 0.45, green: 0.27, blue: 0.15)
}

struct CoffeePanel: View {
    @ObservedObject var model: CoffeeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let p = model.timerProgress { timerBar(p) }
            durations
            Divider()
            options
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    // Große Tasse zum An-/Ausschalten + Status
    private var header: some View {
        HStack(spacing: 12) {
            Button { model.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(model.awake
                              ? AnyShapeStyle(LinearGradient(colors: [.coffee, .coffeeDark],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.primary.opacity(0.08)))
                    Image(systemName: model.awake ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(model.awake ? .white : .secondary)
                }
                .frame(width: 44, height: 44)
                .shadow(color: model.awake ? .coffee.opacity(0.45) : .clear, radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .help(model.manualOn ? "Ausschalten" : "Einschalten")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.headline).font(.headline)
                Text(model.statusLine)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func timerBar(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [.coffee, .coffeeDark], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * (1 - progress)))
                }
            }
            .frame(height: 8)
            HStack {
                Text(model.remainingText ?? "").font(.caption.monospacedDigit())
                Spacer()
                Button("Aus") { model.turnOff() }
                    .buttonStyle(.borderless).font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var durations: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wach halten für").font(.subheadline.weight(.medium))
            HStack(spacing: 5) {
                ForEach(CoffeeModel.durations, id: \.minutes) { d in
                    let selected = model.manualOn && currentMinutes == d.minutes
                    Button { model.turnOn(minutes: d.minutes) } label: {
                        Text(d.short)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? Color.coffee : Color.primary.opacity(0.08)))
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .help(d.long)
                }
            }
        }
    }

    /// Ursprünglich gewählte Dauer (aus Start/Ende abgeleitet)
    private var currentMinutes: Int {
        guard let s = model.manualStart, let u = model.manualUntil else { return 0 }
        return Int((u.timeIntervalSince(s) / 60).rounded())
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Solange Claude Code läuft", isOn: $model.claudeMode)
                if model.claudeMode {
                    Text(model.claudeCount == 0 ? "Keine Claude-Sitzung aktiv"
                         : "\(model.claudeCount) Claude-Prozess\(model.claudeCount == 1 ? "" : "e") aktiv")
                        .font(.caption)
                        .foregroundStyle(model.claudeCount > 0 ? Color.coffee : .secondary)
                        .padding(.leading, 20)
                }
            }
            Toggle("Bildschirm anlassen", isOn: $model.keepDisplay)
            Toggle("Bei Akku unter 20 % ausschalten", isOn: $model.batteryGuard)
            Toggle("Bei Anmeldung starten", isOn: Binding(get: { model.launchAtLogin },
                                                          set: { model.setLaunchAtLogin($0) }))
            HStack {
                Text("Dauer bei Rechtsklick").lineLimit(1)
                Spacer()
                Picker("", selection: $model.defaultMinutes) {
                    ForEach(CoffeeModel.durations, id: \.minutes) { d in Text(d.long).tag(d.minutes) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .toggleStyle(.checkbox)
    }

    private var footer: some View {
        HStack {
            Text("Rechtsklick auf die Tasse: an/aus")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Beenden") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
    }
}
