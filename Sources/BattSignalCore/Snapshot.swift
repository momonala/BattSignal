import Foundation

public enum DeviceKind: String, Codable, Sendable {
    case mac, iphone, ipad, other
}

public struct DeviceInfo: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: DeviceKind
    public var model: String?
    public var osVersion: String?

    public init(id: String, name: String, kind: DeviceKind, model: String? = nil, osVersion: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.model = model
        self.osVersion = osVersion
    }
}

public struct Observer: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Snapshot: Codable, Equatable, Sendable, Identifiable {
    public var device: DeviceInfo
    public var observer: Observer
    public var observedAt: Date
    public var battery: BatteryReading

    public var id: String { device.id }

    public init(device: DeviceInfo, observer: Observer, observedAt: Date, battery: BatteryReading) {
        self.device = device
        self.observer = observer
        self.observedAt = observedAt
        self.battery = battery
    }
}

public struct HistoryPoint: Codable, Equatable, Sendable {
    public var t: Date
    public var level: Int?
    public var health: Double?
    public var cycles: Int?
    public var tempC: Double?
    public var charging: Bool?

    public init(t: Date, level: Int? = nil, health: Double? = nil, cycles: Int? = nil, tempC: Double? = nil, charging: Bool? = nil) {
        self.t = t
        self.level = level
        self.health = health
        self.cycles = cycles
        self.tempC = tempC
        self.charging = charging
    }

    public init(_ snapshot: Snapshot) {
        let b = snapshot.battery
        self.init(
            t: snapshot.observedAt,
            level: b.level,
            health: b.healthPercent.map { ($0 * 10).rounded() / 10 },
            cycles: b.cycleCount,
            tempC: b.temperatureC,
            charging: b.isCharging
        )
    }
}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var lineEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
