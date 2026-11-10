import XCTest
@testable import BattSignalCore

final class BatteryReadingTests: XCTestCase {
    func testMacRegistryMatchesCoconutBattery() {
        let reading = BatteryReading(registry: [
            "CurrentCapacity": 79,
            "MaxCapacity": 100,
            "AppleRawCurrentCapacity": 2990,
            "AppleRawMaxCapacity": 3784,
            "NominalChargeCapacity": 3911,
            "DesignCapacity": 4563,
            "CycleCount": 385,
            "Temperature": 2965,
            "VirtualTemperature": 2329,
            "IsCharging": false,
            "ExternalConnected": true,
            "Voltage": 12304,
            "Amperage": 0,
        ])

        XCTAssertEqual(reading.level, 79)
        XCTAssertEqual(reading.chargePercent, 79)
        XCTAssertEqual(BatteryReading(level: 80, maxCapacityMah: 3797, currentCapacityMah: 3003).chargePercent, 79)
        XCTAssertEqual(BatteryReading(level: 55).chargePercent, 55)
        XCTAssertEqual(reading.maxCapacityMah, 3784)
        XCTAssertEqual(reading.healthPercent!, 82.9, accuracy: 0.05)
        XCTAssertEqual(reading.temperatureC!, 23.29, accuracy: 0.001)
        XCTAssertEqual(reading.isCharging, false)
        XCTAssertEqual(reading.externalPower, true)
    }

    func testIOS27NestedCapacityKeys() {
        let reading = BatteryReading(registry: [
            "CurrentCapacity": 80,
            "MaxCapacity": 100,
            "CycleCount": 34,
            "BatteryData": [
                "AppleRawCurrentCapacity": 6177,
                "AppleRawMaxCapacity": 7932,
                "DesignCapacity": 8152,
            ],
        ])

        XCTAssertEqual(reading.maxCapacityMah, 7932)
        XCTAssertEqual(reading.designCapacityMah, 8152)
        XCTAssertEqual(reading.healthPercent!, 97.3, accuracy: 0.05)
    }

    func testLifetimeDataParsedWithDischargeAsMagnitude() {
        let reading = BatteryReading(registry: [
            "Serial": "F5D2385AB1234CDEF",
            "BatteryData": ["LifetimeData": [
                "TotalOperatingTime": 33745,
                "MinimumPackVoltage": 8852,
                "MaximumPackVoltage": 13308,
                "MaximumChargeCurrent": 5069,
                "MaximumDischargeCurrent": -2835,
                "AverageTemperature": 223,
            ]],
        ])

        XCTAssertEqual(reading.serial, "F5D2385AB1234CDEF")
        XCTAssertEqual(reading.lifetime, LifetimeStats(operatingHours: 33745, minPackVoltageMv: 8852, maxPackVoltageMv: 13308,
                                                       maxChargeCurrentMa: 5069, maxDischargeCurrentMa: 2835))
    }

    func testManufactureWeekDecodedFromSerial() {
        let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
        let utc = { (s: String) in ISO8601DateFormatter().date(from: s + "T00:00:00Z") }

        XCTAssertEqual(BatteryReading(serial: "F5D2385AB1234CDEF").manufactureWeek(now: now), utc("2022-09-19"))
        XCTAssertNil(BatteryReading(serial: "ABCXYZ").manufactureWeek(now: now))
        XCTAssertEqual(BatteryReading(serial: "F5D6505AB1234CDEF").manufactureWeek(now: now), utc("2016-12-12"),
                       "a week later than now in the current year's digit means the previous decade")
    }

    func testChargerDetailsFromAdapter() {
        let reading = BatteryReading(registry: ["AdapterDetails": ["Watts": 15, "Description": "pd charger"]])
        let unplugged = BatteryReading(registry: ["AdapterDetails": ["Watts": 0, "Description": ""]])

        XCTAssertEqual(reading.chargerWatts, 15)
        XCTAssertNil(unplugged.chargerWatts)
    }

    func testDischargeCurrentReportedAsUnsignedWrapsNegative() {
        let wrapped = NSNumber(value: UInt64(bitPattern: -1250))
        let reading = BatteryReading(registry: ["Amperage": wrapped, "Voltage": 12000])

        XCTAssertEqual(reading.amperageMa, -1250)
        XCTAssertEqual(reading.powerWatts!, -15.0, accuracy: 0.001)
    }

    func testChargeStateFirstMatchWins() {
        XCTAssertEqual(BatteryReading(level: 8, isCharging: true, externalPower: true).chargeState, .charging)
        XCTAssertEqual(BatteryReading(level: 100, isCharging: false, externalPower: true, fullyCharged: true).chargeState, .full)
        XCTAssertEqual(BatteryReading(level: 80, isCharging: false, externalPower: true, fullyCharged: false).chargeState, .pluggedIn)
        XCTAssertEqual(BatteryReading(level: 19, isCharging: false, externalPower: false).chargeState, .low)
        XCTAssertEqual(BatteryReading(level: 20, isCharging: false, externalPower: false).chargeState, .onBattery)
        XCTAssertEqual(BatteryReading(level: 100, isCharging: false, externalPower: false).chargeState, .full)
        XCTAssertEqual(BatteryReading().chargeState, .normal)
    }
}
