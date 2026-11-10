import XCTest
@testable import BattSignalCore

final class FleetStoreTests: XCTestCase {
    private var root: URL!
    private var store: FleetStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "battsignal-\(UUID().uuidString)")
        store = FleetStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func snapshot(observer: String, at seconds: TimeInterval, level: Int) -> Snapshot {
        Snapshot(
            device: DeviceInfo(id: "00008110-0000000000000001", name: "Momo", kind: .iphone, model: "iPhone14,5"),
            observer: Observer(id: observer, name: observer),
            observedAt: Date(timeIntervalSince1970: seconds),
            battery: BatteryReading(level: level, cycleCount: 1411, designCapacityMah: 3208, maxCapacityMah: 2533)
        )
    }

    func testNewestObservationWinsAcrossObservers() throws {
        try store.write(snapshot(observer: "mac-air", at: 1_000, level: 50))
        try store.write(snapshot(observer: "mac-pro", at: 2_000, level: 60))

        let all = store.readAll()
        let latest = FleetStore.latestPerDevice(all)

        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(latest.map(\.battery.level), [60])
        XCTAssertEqual(latest.first?.observer.id, "mac-pro")
    }

    func testRewriteReplacesOwnObservation() throws {
        try store.write(snapshot(observer: "mac-air", at: 1_000, level: 50))
        try store.write(snapshot(observer: "mac-air", at: 1_060, level: 51))

        XCTAssertEqual(store.readAll().map(\.battery.level), [51])
    }

    func testHistoryMergesObserversInTimeOrder() throws {
        try store.appendHistory(snapshot(observer: "mac-air", at: 3_000, level: 70))
        try store.appendHistory(snapshot(observer: "mac-pro", at: 1_000, level: 50))
        try store.appendHistory(snapshot(observer: "mac-air", at: 2_000, level: 60))

        let history = store.readHistory(deviceID: "00008110-0000000000000001")

        XCTAssertEqual(history.map(\.level), [50, 60, 70])
        XCTAssertEqual(history.first?.health, 79.0)
    }
}
