import BattSignalCore
import Foundation
import OSLog

private let log = Logger(subsystem: "org.mnalavadi.battsignal", category: "model")

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var local: Snapshot?
    @Published private(set) var devices: [Snapshot] = []
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var saveProblem: String?
    @Published private(set) var lastUpdated: Date?

    private(set) var host = HostIdentity.current()
    let store = FleetStore(root: FleetStore.iCloudRoot)
    private let cli = MobileDeviceCLI.locate()
    private let defaults = UserDefaults.standard

    private var persist: [String: PersistState] = [:]
    private var loops: [Task<Void, Never>] = []
    private var powerWatcher: PowerSourceWatcher?

    private static let localInterval: Duration = .seconds(60)


    init() {
        SettingsKey.registerDefaults()
        loops = [
            Task { [weak self] in
                while !Task.isCancelled {
                    self?.refreshLocal()
                    try? await Task.sleep(for: Self.localInterval)
                }
            },
            Task { [weak self] in
                while !Task.isCancelled {
                    await self?.scanDevices()
                    let minutes = max(self?.defaults.integer(forKey: SettingsKey.scanMinutes) ?? SettingsKey.defaultScanMinutes, 1)
                    try? await Task.sleep(for: .seconds(minutes * 60))
                }
            },
        ]
        powerWatcher = PowerSourceWatcher { [weak self] in self?.refreshLocal() }
    }

    deinit {
        loops.forEach { $0.cancel() }
    }

    var thisMacID: String { host.id }

    func refreshLocal() {
        host = HostIdentity.current()
        if let reading = MacBattery.read() {
            let snapshot = Snapshot(device: host.device, observer: host.observer, observedAt: .now, battery: reading)
            local = snapshot
            record(snapshot)
        }
        reloadFleet()
    }

    func scanDevices() async {
        guard !scanState.isScanning else { return }
        guard let cli else {
            scanState = scanState.applying(.toolMissing)
            return
        }
        scanState = scanState.applying(.started)

        do {
            let found = try await cli.listDevices()
            var failures: [String] = []
            for device in found {
                do {
                    let reading = try await cli.battery(udid: device.udid)
                    record(Snapshot(device: device.info, observer: host.observer, observedAt: .now, battery: reading))
                } catch {
                    log.error("Reading \(device.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    failures.append(device.name)
                }
            }
            scanState = scanState.applying(.listed(deviceCount: found.count, failures: failures, at: .now))
        } catch {
            scanState = scanState.applying(.listFailed(error.localizedDescription))
        }
        log.notice("Scan finished: \(self.scanState.problem?.message ?? "ok", privacy: .public)")
        reloadFleet()
    }

    func history(for deviceID: String) -> [HistoryPoint] {
        store.readHistory(deviceID: deviceID)
    }

    private func record(_ snapshot: Snapshot) {
        var state = persist[snapshot.device.id, default: PersistState()]

        do {
            if try state.writeIfNeeded(snapshot, using: store.write) { saveProblem = nil }
        } catch {
            saveProblem = "Couldn't save to iCloud Drive: \(error.localizedDescription)"
        }

        do {
            try state.appendHistoryIfNeeded(snapshot, using: store.appendHistory)
        } catch {
            log.error("History append for \(snapshot.device.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }

        persist[snapshot.device.id] = state
    }

    private func reloadFleet() {
        let all = FleetStore.latestPerDevice(store.readAll() + [local].compactMap { $0 })
        let localID = host.id
        devices = all.sorted { a, b in
            if (a.id == localID) != (b.id == localID) { return a.id == localID }
            if a.device.kind != b.device.kind { return a.device.kind.sortOrder < b.device.kind.sortOrder }
            return a.device.name.localizedStandardCompare(b.device.name) == .orderedAscending
        }
        lastUpdated = .now
    }
}

extension DeviceKind {
    var sortOrder: Int {
        switch self {
        case .mac: 0
        case .iphone: 1
        case .ipad: 2
        case .other: 3
        }
    }

    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .iphone: "iphone"
        case .ipad: "ipad"
        case .other: "battery.75percent"
        }
    }
}
