import Foundation

public enum HistoryMetric: String, CaseIterable, Identifiable, Sendable {
    case health = "Health"
    case cycles = "Cycles"

    public var id: Self { self }
}

public struct ChartPoint: Identifiable, Equatable, Sendable {
    public var date: Date
    public var value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct WearPoint: Identifiable, Equatable, Sendable {
    public var cycles: Int
    public var health: Double
    public var id: Int { cycles }

    public init(cycles: Int, health: Double) {
        self.cycles = cycles
        self.health = health
    }
}

public struct WearTrend: Equatable, Sendable {
    public var slopePerCycle: Double
    public var intercept: Double

    public func health(atCycles cycles: Int) -> Double { intercept + slopePerCycle * Double(cycles) }

    /// Positive number: health percentage points lost per 100 cycles.
    public var lossPer100Cycles: Double { -slopePerCycle * 100 }
}

public struct UsageRates: Equatable, Sendable {
    public var cyclesPerMonth: Double?
    public var healthChangePerMonth: Double?
}

public struct TemperatureStats: Equatable, Sendable {
    public var min: Double
    public var max: Double
}

public enum HistoryAggregator {
    public static func temperatureStats(_ points: [HistoryPoint]) -> TemperatureStats? {
        let temps = points.compactMap(\.tempC)
        guard let low = temps.min(), let high = temps.max() else { return nil }
        return TemperatureStats(min: low, max: high)
    }

    /// Buckets points into fixed windows: health is averaged, cycles take the maximum.
    /// Each bucket is dated at its newest reading, so the line reaches the latest data.
    public static func series(_ points: [HistoryPoint], metric: HistoryMetric, since: Date?, bucket: TimeInterval) -> [ChartPoint] {
        let inRange = points.filter { since == nil || $0.t >= since! }
        let grouped = Dictionary(grouping: inRange) { floor($0.t.timeIntervalSince1970 / bucket) }
        return grouped.values.compactMap { bucketPoints -> ChartPoint? in
            let value: Double?
            switch metric {
            case .health: value = average(bucketPoints.compactMap(\.health))
            case .cycles: value = bucketPoints.compactMap(\.cycles).max().map(Double.init)
            }
            guard let value, let newest = bucketPoints.map(\.t).max() else { return nil }
            return ChartPoint(date: newest, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    /// Average health at each cycle count, for plotting wear against use rather than time.
    public static func healthByCycles(_ points: [HistoryPoint], since: Date?) -> [WearPoint] {
        let inRange = points.filter { since == nil || $0.t >= since! }
        var byCycles: [Int: [Double]] = [:]
        for point in inRange {
            guard let cycles = point.cycles, let health = point.health else { continue }
            byCycles[cycles, default: []].append(health)
        }
        return byCycles
            .compactMap { cycles, values in average(values).map { WearPoint(cycles: cycles, health: $0) } }
            .sorted { $0.cycles < $1.cycles }
    }

    /// Least-squares trend of health against cycles. Nil until there are at least 10 cycles of spread.
    public static func trend(_ points: [WearPoint]) -> WearTrend? {
        guard let first = points.first?.cycles, let last = points.last?.cycles, last - first >= 10,
              let fit = leastSquares(points.map { (Double($0.cycles), $0.health) })
        else { return nil }
        return WearTrend(slopePerCycle: fit.slope, intercept: fit.intercept)
    }

    /// Cycles and health change per month, fitted over daily averages so dense recent readings don't dominate.
    /// Nil until the history spans at least 14 days.
    public static func usageRates(_ points: [HistoryPoint]) -> UsageRates? {
        let sorted = points.sorted { $0.t < $1.t }
        guard let start = sorted.first?.t, let end = sorted.last?.t,
              end.timeIntervalSince(start) >= 14 * 86_400
        else { return nil }

        let days = Dictionary(grouping: sorted) { floor($0.t.timeIntervalSince(start) / 86_400) }
        let cycles = days.compactMap { day, pts in pts.compactMap(\.cycles).max().map { (day, Double($0)) } }
        let health = days.compactMap { day, pts in average(pts.compactMap(\.health)).map { (day, $0) } }
        let daysPerMonth = 30.44

        return UsageRates(
            cyclesPerMonth: leastSquares(cycles).map { $0.slope * daysPerMonth },
            healthChangePerMonth: leastSquares(health).map { $0.slope * daysPerMonth }
        )
    }

    private static func leastSquares(_ pairs: [(Double, Double)]) -> (slope: Double, intercept: Double)? {
        guard pairs.count >= 2 else { return nil }
        let n = Double(pairs.count)
        let meanX = pairs.reduce(0) { $0 + $1.0 } / n
        let meanY = pairs.reduce(0) { $0 + $1.1 } / n
        let sxx = pairs.reduce(0) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
        guard sxx > 0 else { return nil }
        let sxy = pairs.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx
        return (slope, meanY - slope * meanX)
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
