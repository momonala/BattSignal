import AppKit
import BattSignalCore
import SwiftUI

enum SettingsKey {
    static let showPercent = "showPercentInMenuBar"
    static let powerSymbol = "menuBarPowerSymbol"
    static let iconColoring = "menuBarIconColoring"
    static let barColoring = "chargeBarColoring"
    static let scanMinutes = "scanIntervalMinutes"

    static let defaultScanMinutes = 15

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showPercent: true,
            scanMinutes: defaultScanMinutes,
        ])
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(SettingsKey.showPercent) private var showPercent = true
    @AppStorage(SettingsKey.powerSymbol) private var powerSymbol = PowerSymbol.bolt
    @AppStorage(SettingsKey.iconColoring) private var iconColoring = IconColoring.symbolAndNumber
    @AppStorage(SettingsKey.barColoring) private var barColoring = BarColoring.blue
    @AppStorage(SettingsKey.scanMinutes) private var scanMinutes = SettingsKey.defaultScanMinutes
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("General") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        do {
                            try LoginItem.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = "Couldn't change the login item: \(error.localizedDescription)"
                            openAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).foregroundStyle(.red).font(.caption)
                }
                Toggle("Show charge % next to the bat", isOn: $showPercent)
                pickerRow("When plugged in, show", selection: $powerSymbol) {
                    Text("Lightning bolt").tag(PowerSymbol.bolt)
                    Text("Plug").tag(PowerSymbol.plug)
                }
                pickerRow("Color", selection: $iconColoring) {
                    Text("Symbol only").tag(IconColoring.symbolOnly)
                    Text("Symbol and charge %").tag(IconColoring.symbolAndNumber)
                    Text("Symbol, charge % and bat").tag(IconColoring.wholeIcon)
                }
                pickerRow("Charge bars", selection: $barColoring) {
                    Text("Always blue").tag(BarColoring.blue)
                    Text("Match menu bar colors").tag(BarColoring.chargeState)
                }
                HStack {
                    Text("Charge limit on this Mac")
                    Spacer()
                    Text(model.local?.battery.chargeLimit.map { "\($0) %" } ?? "Not set")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Change…") { NSWorkspace.shared.open(ChargeLimit.settingsURL) }
                }
            }

            section("iPhone and iPad") {
                pickerRow("Check every", selection: $scanMinutes) {
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }

            }

            section("Data") {
                HStack {
                    Text("Saved in iCloud Drive › BattSignal")
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.root])
                    }
                }
            }
        }
        .toggleStyle(TrailingCheckboxStyle())
    }

    private func pickerRow<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        @ViewBuilder options: () -> some View
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection, content: options)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(title).font(.subheadline).fontWeight(.semibold)
        }
    }
}

private struct TrailingCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Toggle("", isOn: configuration.$isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
        }
    }
}
