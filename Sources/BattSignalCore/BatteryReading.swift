import Foundation

public struct BatteryReading: Codable, Equatable, Sendable {
    public var level: Int?
    public var isCharging: Bool?
    public var externalPower: Bool?
    public var fullyCharged: Bool?
    public var cycleCount: Int?
    public var designCapacityMah: Int?
    public var maxCapacityMah: Int?
    public var currentCapacityMah: Int?
    public var temperatureC: Double?
    public var voltageMv: Int?
    public var amperageMa: Int?
    public var serial: String?
    public var lifetime: LifetimeStats?
    public var chargerWatts: Int?
    /// macOS charge limit in percent; Macs only.
    public var chargeLimit: Int?

    public init(
        level: Int? = nil,
        isCharging: Bool? = nil,
        externalPower: Bool? = nil,
        fullyCharged: Bool? = nil,
        cycleCount: Int? = nil,
        designCapacityMah: Int? = nil,
        maxCapacityMah: Int? = nil,
        currentCapacityMah: Int? = nil,
        temperatureC: Double? = nil,
        voltageMv: Int? = nil,
        amperageMa: Int? = nil,
        serial: String? = nil,
        lifetime: LifetimeStats? = nil,
        chargerWatts: Int? = nil,
        chargeLimit: Int? = nil
    ) {
        self.level = level
        self.isCharging = isCharging
        self.externalPower = externalPower
        self.fullyCharged = fullyCharged
        self.cycleCount = cycleCount
        self.designCapacityMah = designCapacityMah
        self.maxCapacityMah = maxCapacityMah
        self.currentCapacityMah = currentCapacityMah
        self.temperatureC = temperatureC
        self.voltageMv = voltageMv
        self.amperageMa = amperageMa
        self.serial = serial
        self.lifetime = lifetime
        self.chargerWatts = chargerWatts
        self.chargeLimit = chargeLimit
    }

    /// Parses an `AppleSmartBattery` IORegistry dictionary. Macs and iOS devices report the same keys,
    /// except that iOS 27 moved the capacity keys into the nested `BatteryData` dictionary.
    public init(registry: [String: Any]) {
        let nested = registry["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? {
            guard let number = (registry[key] ?? nested[key]) as? NSNumber else { return nil }
            return Int(truncatingIfNeeded: number.int64Value)
        }
        self.init(
            level: int("CurrentCapacity"),
            isCharging: registry["IsCharging"] as? Bool,
            externalPower: registry["ExternalConnected"] as? Bool,
            fullyCharged: registry["FullyCharged"] as? Bool,
            cycleCount: int("CycleCount"),
            designCapacityMah: int("DesignCapacity"),
            maxCapacityMah: int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity"),
            currentCapacityMah: int("AppleRawCurrentCapacity"),
            temperatureC: (int("VirtualTemperature") ?? int("Temperature")).map { Double($0) / 100 },
            voltageMv: int("Voltage"),
            amperageMa: int("Amperage"),
            serial: registry["Serial"] as? String,
            lifetime: (nested["LifetimeData"] as? [String: Any]).map(LifetimeStats.init(registry:)),
            chargerWatts: ((registry["AdapterDetails"] as? [String: Any])?["Watts"] as? NSNumber).map(\.intValue).flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// Charge as the fuel gauge's raw ratio (current mAh ÷ full-charge mAh), like coconutBattery.
    /// `level` stays macOS's smoothed percentage, which is what the macOS charge limit is enforced against.
    public var chargePercent: Int? {
        guard let current = currentCapacityMah, let full = maxCapacityMah, full > 0 else { return level }
        return min(100, Int((Double(current) / Double(full) * 100).rounded()))
    }

    public var healthPercent: Double? {
        guard let max = maxCapacityMah, let design = designCapacityMah, design > 0 else { return nil }
        return Double(max) / Double(design) * 100
    }

    /// Apple battery serials encode the build week: 4th character = last digit of the year, 5th–6th = ISO week.
    /// Decoded against `now` so the year digit resolves to the most recent matching year.
    public func manufactureWeek(now: Date = .now) -> Date? {
        guard let serial, serial.count >= 6 else { return nil }
        let chars = Array(serial)
        guard let yearDigit = chars[3].wholeNumberValue,
              let week = Int(String(chars[4...5])), (1...53).contains(week)
        else { return nil }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let currentYear = calendar.component(.yearForWeekOfYear, from: now)
        let year = currentYear - ((currentYear - yearDigit) % 10 + 10) % 10
        guard let date = calendar.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year)) else { return nil }
        return date > now
            ? calendar.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year - 10))
            : date
    }

    /// Plugged in, not charging, and sitting at (or within a point of) the macOS charge limit.
    public var isHeldAtLimit: Bool {
        guard let limit = chargeLimit, limit < 100, let level,
              externalPower == true, isCharging != true
        else { return false }
        return level >= limit - 1 && level <= limit + 1
    }

    public var chargeState: ChargeState {
        if isCharging == true { return .charging }
        if fullyCharged == true { return .full }
        if externalPower == true { return .pluggedIn }
        guard let percent = chargePercent else { return .normal }
        if percent < 20 { return .low }
        if (level ?? percent) >= 100 { return .full }
        return .onBattery
    }

    public var powerWatts: Double? {
        guard let voltageMv, let amperageMa else { return nil }
        return Double(voltageMv) * Double(amperageMa) / 1_000_000
    }
}

public enum ChargeState: Sendable {
    case normal, charging, full, pluggedIn, low, onBattery
}

/// Running totals the battery's gauge keeps since manufacture. Temperatures are left out: their units differ
/// between keys and between devices, so BattSignal derives temperature ranges from its own readings instead.
public struct LifetimeStats: Codable, Equatable, Sendable {
    public var operatingHours: Int?
    public var minPackVoltageMv: Int?
    public var maxPackVoltageMv: Int?
    public var maxChargeCurrentMa: Int?
    public var maxDischargeCurrentMa: Int?

    public init(operatingHours: Int? = nil, minPackVoltageMv: Int? = nil, maxPackVoltageMv: Int? = nil,
                maxChargeCurrentMa: Int? = nil, maxDischargeCurrentMa: Int? = nil) {
        self.operatingHours = operatingHours
        self.minPackVoltageMv = minPackVoltageMv
        self.maxPackVoltageMv = maxPackVoltageMv
        self.maxChargeCurrentMa = maxChargeCurrentMa
        self.maxDischargeCurrentMa = maxDischargeCurrentMa
    }

    public init(registry: [String: Any]) {
        func int(_ key: String) -> Int? {
            (registry[key] as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) }
        }
        self.init(
            operatingHours: int("TotalOperatingTime"),
            minPackVoltageMv: int("MinimumPackVoltage"),
            maxPackVoltageMv: int("MaximumPackVoltage"),
            maxChargeCurrentMa: int("MaximumChargeCurrent"),
            maxDischargeCurrentMa: int("MaximumDischargeCurrent").map(abs)
        )
    }
}
