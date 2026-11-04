import XCTest
@testable import BattSignalCore

final class ChargeLimitTests: XCTestCase {
    private func preferences(limit: Int, terminated: Bool = false, reason: String = "manualChargeLimit") throws -> Data {
        let archive: [String: Any] = [
            "$archiver": "NSKeyedArchiver",
            "$objects": ["$null", ["soclimit": limit, "terminated": terminated, "drain": true], reason],
        ]
        let policies = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        return try PropertyListSerialization.data(fromPropertyList: ["policies": policies], format: .binary, options: 0)
    }

    func testReadsActiveManualLimit() throws {
        XCTAssertEqual(ChargeLimit.parse(preferences: try preferences(limit: 80)), 80)
        XCTAssertNil(ChargeLimit.parse(preferences: try preferences(limit: 80, terminated: true)))
        XCTAssertNil(ChargeLimit.parse(preferences: try preferences(limit: 80, reason: "somethingElse")))
        XCTAssertNil(ChargeLimit.parse(preferences: Data("not a plist".utf8)))
    }

    func testHeldAtLimit() {
        let held = BatteryReading(level: 80, isCharging: false, externalPower: true, chargeLimit: 80)
        let overshoot = BatteryReading(level: 84, isCharging: true, externalPower: true, chargeLimit: 80)

        XCTAssertTrue(held.isHeldAtLimit)
        XCTAssertFalse(overshoot.isHeldAtLimit)
    }
}

final class HistoryAggregatorTests: XCTestCase {
    func testBucketsAverageHealthAndTakeMaxCycles() {
        let points = [
            HistoryPoint(t: Date(timeIntervalSince1970: 0), level: 40, health: 82, cycles: 384),
            HistoryPoint(t: Date(timeIntervalSince1970: 1_800), level: 60, health: 84, cycles: 385),
            HistoryPoint(t: Date(timeIntervalSince1970: 3_600), level: 80, health: 83, cycles: 385),
        ]

        let health = HistoryAggregator.series(points, metric: .health, since: nil, bucket: 3_600)
        let cycles = HistoryAggregator.series(points, metric: .cycles, since: nil, bucket: 3_600)
        let recent = HistoryAggregator.series(points, metric: .health, since: Date(timeIntervalSince1970: 3_000), bucket: 3_600)

        XCTAssertEqual(health.map(\.value), [83, 83])
        XCTAssertEqual(cycles.map(\.value), [385, 385])
        XCTAssertEqual(cycles.map(\.date.timeIntervalSince1970), [1_800, 3_600])
        XCTAssertEqual(recent.map(\.value), [83])
    }

    func testHealthByCyclesAveragesPerCycleAndFitsTrend() throws {
        let points = [
            HistoryPoint(t: Date(timeIntervalSince1970: 0), health: 79.5, cycles: 1308),
            HistoryPoint(t: Date(timeIntervalSince1970: 1), health: 79.4, cycles: 1350),
            HistoryPoint(t: Date(timeIntervalSince1970: 2), health: 79.0, cycles: 1411),
            HistoryPoint(t: Date(timeIntervalSince1970: 3), health: 78.8, cycles: 1411),
            HistoryPoint(t: Date(timeIntervalSince1970: 4), level: 50),
        ]

        let wear = HistoryAggregator.healthByCycles(points, since: nil)
        let trend = try XCTUnwrap(HistoryAggregator.trend(wear))

        XCTAssertEqual(wear.map(\.cycles), [1308, 1350, 1411])
        XCTAssertEqual(wear.last!.health, 78.9, accuracy: 0.001)
        XCTAssertEqual(trend.lossPer100Cycles, 0.57, accuracy: 0.05)
    }

    func testUsageRatesFitDailyAveragesPerMonth() throws {
        let day = 86_400.0
        var points: [HistoryPoint] = (0..<60).map { i in
            HistoryPoint(t: Date(timeIntervalSince1970: Double(i) * day), health: 90 - 0.1 * Double(i), cycles: 100 + i / 2)
        }
        points += (0..<50).map { _ in HistoryPoint(t: Date(timeIntervalSince1970: 59 * day + 60), health: 84.1, cycles: 129) }

        let rates = try XCTUnwrap(HistoryAggregator.usageRates(points))

        XCTAssertEqual(rates.cyclesPerMonth!, 15.2, accuracy: 0.3)
        XCTAssertEqual(rates.healthChangePerMonth!, -3.04, accuracy: 0.05)
    }

    func testUsageRatesNeedTwoWeeksOfHistory() {
        let points = [
            HistoryPoint(t: Date(timeIntervalSince1970: 0), health: 83, cycles: 380),
            HistoryPoint(t: Date(timeIntervalSince1970: 10 * 86_400), health: 82.9, cycles: 385),
        ]

        XCTAssertNil(HistoryAggregator.usageRates(points))
    }

    func testTrendNeedsSpreadOfCycles() {
        let wear = [WearPoint(cycles: 385, health: 82.9), WearPoint(cycles: 388, health: 82.7)]

        XCTAssertNil(HistoryAggregator.trend(wear))
    }
}

final class IOSDeviceParsingTests: XCTestCase {
    func testUsbmuxListDedupesDeviceSeenOverUSBAndWiFi() throws {
        let json = """
        [
          {"ConnectionType": "Network", "DeviceClass": "iPhone", "DeviceName": "Momo",
           "ProductType": "iPhone14,5", "UniqueDeviceID": "00008110-0000000000000001"},
          {"ConnectionType": "USB", "DeviceClass": "iPhone", "DeviceName": "Momo",
           "ProductType": "iPhone14,5", "UniqueDeviceID": "00008110-0000000000000001"},
          {"ConnectionType": "Network", "DeviceClass": "iPad", "DeviceName": "Studio iPad",
           "ProductType": "iPad13,4", "UniqueDeviceID": "00008103-AAAA"}
        ]
        """

        let devices = try IOSDevice.parseList(Data(json.utf8))

        XCTAssertEqual(devices.map(\.name), ["Momo", "Studio iPad"])
        XCTAssertEqual(devices.map(\.kind), [.iphone, .ipad])
    }

    func testIOSDeviceCarriesOSVersion() throws {
        let json = #"[{"DeviceClass": "iPhone", "DeviceName": "Momo", "ProductVersion": "26.7.1", "UniqueDeviceID": "X"}]"#
        let device = try XCTUnwrap(IOSDevice.parseList(Data(json.utf8)).first)

        XCTAssertEqual(device.info.osVersion, "iOS 26.7.1")
    }

    func testProductNameFallsBackToIdentifier() {
        XCTAssertEqual(ProductNames.display("iPhone14,5"), "iPhone 13")
        XCTAssertEqual(ProductNames.display("Mac17,9"), "Mac17,9")
    }
}
