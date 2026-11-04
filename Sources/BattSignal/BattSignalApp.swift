import BattSignalCore
import SwiftUI

@main
struct BattSignalApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @AppStorage(SettingsKey.showPercent) private var showPercent = true
    @AppStorage(SettingsKey.powerSymbol) private var powerSymbol = PowerSymbol.bolt
    @AppStorage(SettingsKey.iconColoring) private var iconColoring = IconColoring.symbolAndNumber

    var body: some View {
        Image(nsImage: MenuIcon.image(
            for: model.local?.battery,
            showPercent: showPercent,
            powerSymbol: powerSymbol,
            coloring: iconColoring
        ))
    }
}
