import Foundation

public struct PersistState: Equatable, Sendable {
    public static let observationMaxAge: TimeInterval = 10 * 60
    public static let historyInterval: TimeInterval = 15 * 60 - 30

    public private(set) var written: Snapshot?
    public private(set) var historyAppendedAt: Date?

    public init() {}

    public func needsWrite(_ snapshot: Snapshot) -> Bool {
        guard let written else { return true }
        return written.battery.level != snapshot.battery.level
            || written.battery.isCharging != snapshot.battery.isCharging
            || written.battery.externalPower != snapshot.battery.externalPower
            || snapshot.observedAt.timeIntervalSince(written.observedAt) >= Self.observationMaxAge
    }

    public func needsHistory(_ snapshot: Snapshot) -> Bool {
        snapshot.observedAt.timeIntervalSince(historyAppendedAt ?? .distantPast) >= Self.historyInterval
    }

    public mutating func didWrite(_ snapshot: Snapshot) {
        written = snapshot
    }

    public mutating func didAppendHistory(_ snapshot: Snapshot) {
        historyAppendedAt = snapshot.observedAt
    }
}
