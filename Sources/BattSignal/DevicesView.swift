import BattSignalCore
import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                ForEach(model.devices) { snapshot in
                    let isExpanded = expandedID == snapshot.id
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            expandedID = isExpanded ? nil : snapshot.id
                        } label: {
                            DeviceRow(
                                snapshot: snapshot,
                                thisMacID: model.thisMacID,
                                isExpanded: isExpanded,
                                isCompact: expandedID != nil && !isExpanded
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(isExpanded ? "Hides history" : "Shows history")

                        if isExpanded {
                            ExpandedDevice(snapshot: snapshot)
                                .padding(.bottom, 12)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
                        }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                    if snapshot.id != model.devices.last?.id {
                        Divider()
                    }
                }
            }
            .animation(Motion.animation(Motion.reveal, reduceMotion: reduceMotion), value: model.devices.map(\.id))
            .animation(Motion.animation(Motion.reveal, reduceMotion: reduceMotion), value: expandedID)

            if model.scanState.isScanning {
                Text("Looking for iPhones and iPads on this Wi-Fi…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .shimmer(true)
                    .transition(.opacity)
            } else if let problem = model.scanState.problem?.message ?? model.saveProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }
}

/// Loads a device's history once and shares it between the stats grid and the chart.
private struct ExpandedDevice: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: Snapshot
    @State private var points: [HistoryPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeviceDetails(
                snapshot: snapshot,
                rates: HistoryAggregator.usageRates(points),
                temperatures: HistoryAggregator.temperatureStats(points)
            )
            HistoryView(points: points)
        }
        .task(id: snapshot.id) {
            points = model.history(for: snapshot.id)
        }
    }
}

/// Expanded stats: titled sections of 3-column, label-over-value cells.
private struct DeviceDetails: View {
    let snapshot: Snapshot
    let rates: UsageRates?
    let temperatures: TemperatureStats?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openSections: Set<String> = []

    private typealias Cell = (label: String, value: String)
    private static let collapsedByDefault: Set<String> = ["Lifetime"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = section.title {
                        if Self.collapsedByDefault.contains(title) {
                            let isOpen = openSections.contains(title)
                            Button {
                                if isOpen { openSections.remove(title) } else { openSections.insert(title) }
                            } label: {
                                HStack(spacing: 4) {
                                    sectionTitle(title)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .scaleEffect(y: isOpen ? -1 : 1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(isOpen ? "Hides \(title)" : "Shows \(title)")
                            if isOpen {
                                grid(section.cells)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
                            }
                        } else {
                            sectionTitle(title)
                            grid(section.cells)
                        }
                    } else {
                        grid(section.cells)
                    }
                }
            }
        }
        .animation(Motion.animation(Motion.reveal, reduceMotion: reduceMotion), value: openSections)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
    }

    private var sections: [(title: String?, cells: [Cell])] {
        let battery = snapshot.battery
        let lifetime = battery.lifetime
        let result: [(title: String?, cells: [Cell])] = [
            (nil, [
                ("Health", Format.percent(battery.healthPercent)),
                ("Cycles", battery.cycleCount.map { $0.formatted() } ?? "–"),
                ("Temperature", Format.temperature(battery.temperatureC)),
                ("Charge now", Format.mah(battery.currentCapacityMah)),
                ("Full charge", Format.mah(battery.maxCapacityMah)),
                ("Design", Format.mah(battery.designCapacityMah)),
                ("Cycles / month", rates?.cyclesPerMonth.map { String(format: "%.0f", $0) } ?? "–"),
                ("Health / month", rates?.healthChangePerMonth.map { String(format: "%+.2f %%", $0) } ?? "–"),
            ]),
            ("Lifetime", [
                ("Operating time", Format.duration(hours: lifetime?.operatingHours)),
                ("Voltage range", Format.voltageRange(lifetime?.minPackVoltageMv, lifetime?.maxPackVoltageMv)),
                ("Temp seen", temperatures.map { String(format: "%.0f–%.0f °C", $0.min, $0.max) } ?? "–"),
                ("Peak charge", Format.amps(lifetime?.maxChargeCurrentMa)),
                ("Peak discharge", Format.amps(lifetime?.maxDischargeCurrentMa)),
                ("Battery made", battery.manufactureWeek().map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "–"),
            ]),
            ("Device", [
                ("System", snapshot.device.osVersion ?? "–"),
                ("Charger", Format.charger(battery)),
                ("Battery serial", battery.serial ?? "–"),
            ] + (snapshot.device.kind == .mac ? [("Charge limit", battery.chargeLimit.map { "\($0) %" } ?? "Not set")] : [])),
        ]
        return result
    }

    private func grid(_ cells: [Cell]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            ForEach(0..<((cells.count + 2) / 3), id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if index < cells.count {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cells[index].label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(cells[index].value)
                                    .font(.callout)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .numericPop(cells[index].value)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.barColoring) private var barColoring = BarColoring.blue
    let snapshot: Snapshot
    let thisMacID: String
    let isExpanded: Bool
    let isCompact: Bool

    var body: some View {
        let battery = snapshot.battery
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.device.kind.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(snapshot.device.name).fontWeight(.semibold)
                    if let model = ProductNames.display(snapshot.device.model), snapshot.device.kind != .mac {
                        Text(model).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if battery.isCharging == true {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.secondary)
                            .transition(.scale(scale: 0.25).combined(with: .opacity))
                    }
                    Text(battery.chargePercent.map { "\($0) %" } ?? "–").monospacedDigit().numericPop(battery.chargePercent)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .scaleEffect(y: isExpanded ? -1 : 1)
                }
                .animation(Motion.iconSwap, value: battery.isCharging)
            if !isCompact {
                ProgressView(value: Double(battery.chargePercent ?? 0), total: 100)
                    .tint(barColoring == .chargeState ? battery.chargeState.tint.map { Color(nsColor: $0) } : nil)
                    .animation(Motion.resize, value: battery.chargePercent)
                HStack {
                    Text(captionText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id(isExpanded)
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                    Spacer(minLength: 8)
                    Text(seenText).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .padding(.vertical, isCompact ? 5 : 10)
        .contentShape(Rectangle())
    }

    private var captionText: String {
        let battery = snapshot.battery
        if isExpanded { return Format.powerStatus(battery) }
        return [
            "Health \(Format.percent(battery.healthPercent))",
            "\(battery.cycleCount.map { $0.formatted() } ?? "–") cycles",
            Format.powerStatus(battery),
        ]
        .joined(separator: " · ")
    }

    private var seenText: String {
        if snapshot.id == thisMacID { return "this Mac, now" }
        return Format.seen(snapshot.observedAt)
    }
}
