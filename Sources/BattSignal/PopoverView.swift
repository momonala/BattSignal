import BattSignalCore
import SwiftUI

struct PopoverView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(showingSettings ? "Settings" : "Devices")
                    .font(.headline)
                Spacer()
                Button {
                    showingSettings.toggle()
                } label: {
                    Image(systemName: showingSettings ? "gearshape.fill" : "gearshape")
                        .font(.title3)
                        .foregroundStyle(showingSettings ? Color.accentColor : .secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(showingSettings ? "Back to devices" : "Settings")
                .accessibilityLabel(showingSettings ? "Back to devices" : "Settings")
            }

            Group {
                if showingSettings {
                    SettingsView()
                } else {
                    DevicesView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .id(showingSettings)
            .transition(Motion.tabContent(reduceMotion: reduceMotion))

            FooterView()
        }
        .padding(16)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowFitsContent())
        .animation(Motion.animation(Motion.resize, reduceMotion: reduceMotion), value: showingSettings)
    }
}

struct FooterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Text(model.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Starting…")
                    .foregroundStyle(.secondary)
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .foregroundStyle(.tertiary)
                Spacer()
                SuccessCheck(trigger: model.lastScanSucceededAt)
                Button("Scan now") {
                    Task { await model.scanDevices() }
                }
                .disabled(model.isScanning)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
            .controlSize(.small)
        }
    }
}

enum Format {
    static func mah(_ value: Int?) -> String {
        value.map { "\($0.formatted()) mAh" } ?? "–"
    }

    static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f %%", $0) } ?? "–"
    }

    static func temperature(_ value: Double?) -> String {
        value.map { String(format: "%.1f °C", $0) } ?? "–"
    }

    static func powerStatus(_ battery: BatteryReading) -> String {
        let watts = abs(battery.powerWatts ?? 0)
        let rate = watts >= 0.05 ? String(format: " %.1f W", watts) : nil
        if battery.isHeldAtLimit, let limit = battery.chargeLimit { return "Held at \(limit) % limit" }
        if battery.fullyCharged == true { return "Fully charged" }
        if battery.isCharging == true { return rate.map { "Charging at\($0)" } ?? "Charging" }
        if battery.externalPower == true { return "Plugged in, not charging" }
        return rate.map { "On battery, using\($0)" } ?? "On battery"
    }

    static func duration(hours: Int?) -> String {
        guard let hours else { return "–" }
        if hours >= 24 * 365 { return String(format: "%.1f years", Double(hours) / (24 * 365)) }
        if hours >= 48 { return "\(hours / 24) days" }
        return "\(hours) h"
    }

    static func voltageRange(_ minMv: Int?, _ maxMv: Int?) -> String {
        guard let minMv, let maxMv else { return "–" }
        return String(format: "%.1f–%.1f V", Double(minMv) / 1000, Double(maxMv) / 1000)
    }

    static func amps(_ milliamps: Int?) -> String {
        milliamps.map { String(format: "%.1f A", Double($0) / 1000) } ?? "–"
    }

    static func charger(_ battery: BatteryReading) -> String {
        guard battery.externalPower == true else { return "Unplugged" }
        guard let watts = battery.chargerWatts else { return "Plugged in" }
        return "\(watts) W"
    }

    static func seen(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        let ago = switch seconds {
        case ..<90: "just now"
        case ..<3_600: "\(Int((seconds / 60).rounded())) min ago"
        case ..<86_400: "\(Int((seconds / 3_600).rounded())) h ago"
        default: "\(Int((seconds / 86_400).rounded())) d ago"
        }
        let time = Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "\(time) (\(ago))"
    }
}
