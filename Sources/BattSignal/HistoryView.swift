import BattSignalCore
import Charts
import SwiftUI

struct HistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let points: [HistoryPoint]
    @State private var kind: ChartKind = .health
    @State private var range: ChartRange = .all
    @State private var hoveredDate: Date?
    @State private var hoveredCycles: Int?

    private var animation: Animation? { Motion.animation(Motion.resize, reduceMotion: reduceMotion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SegmentedBar(options: ChartKind.allCases.map { ($0, $0.rawValue) }, selection: $kind)
            SegmentedBar(options: ChartRange.allCases.map { ($0, $0.rawValue) }, selection: $range)

            Group {
                if let metric = kind.metric {
                    timeChart(HistoryAggregator.series(points, metric: metric, since: range.since, bucket: 86_400), metric: metric)
                } else {
                    wearChart(HistoryAggregator.healthByCycles(points, since: range.since))
                }
            }
            .frame(height: 220)
        }
    }

    @ViewBuilder
    private func timeChart(_ data: [ChartPoint], metric: HistoryMetric) -> some View {
        if data.isEmpty {
            emptyState
        } else {
            let domain = yDomain(data.map(\.value), metric: metric)
            let selected = hoveredDate.flatMap { date in
                data.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            }

            Chart {
                ForEach(data) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", domain.lowerBound),
                        yEnd: .value(metric.rawValue, point.value)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.12))
                    .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                        .interpolationMethod(.monotone)
                    if data.count < 40 {
                        PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                            .symbolSize(18)
                    }
                }
                if let selected {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(title: selected.date.formatted(.dateTime.day().month(.abbreviated).year()), value: valueText(selected.value, metric: metric))
                        }
                    PointMark(x: .value("Date", selected.date), y: .value(metric.rawValue, selected.value))
                        .symbolSize(70)
                }
            }
            .chartYScale(domain: domain)
            .chartXSelection(value: $hoveredDate)
            .animation(animation, value: data)
        }
    }

    @ViewBuilder
    private func wearChart(_ data: [WearPoint]) -> some View {
        if data.isEmpty {
            emptyState
        } else {
            let trend = HistoryAggregator.trend(data)
            let domain = yDomain(data.map(\.health), metric: .health)
            let xDomain = (data.first!.cycles - 5)...(data.last!.cycles + 5)
            let selected = hoveredCycles.flatMap { cycles in data.min { abs($0.cycles - cycles) < abs($1.cycles - cycles) } }

            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    if let trend {
                        ForEach([xDomain.lowerBound, xDomain.upperBound], id: \.self) { cycles in
                            LineMark(x: .value("Cycles", cycles), y: .value("Trend", trend.health(atCycles: cycles)), series: .value("Line", "Trend"))
                                .foregroundStyle(Color.mustard)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }
                    }
                    ForEach(data) { point in
                        PointMark(x: .value("Cycles", point.cycles), y: .value("Health", point.health))
                            .symbolSize(data.count < 60 ? 30 : 14)
                    }
                    if let selected {
                        RuleMark(x: .value("Cycles", selected.cycles))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                tooltip(title: "\(selected.cycles.formatted()) cycles", value: valueText(selected.health, metric: .health))
                            }
                        PointMark(x: .value("Cycles", selected.cycles), y: .value("Health", selected.health))
                            .symbolSize(80)
                    }
                }
                .chartXScale(domain: xDomain)
                .chartYScale(domain: domain)
                .chartXAxisLabel("Cycles")
                .chartXSelection(value: $hoveredCycles)
                .animation(animation, value: data)

                Text(trendCaption(trend))
                    .font(.caption)
                    .foregroundStyle(trend == nil ? Color.secondary : Color.mustard)
                    .numericPop(trendCaption(trend))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No history yet",
            systemImage: "chart.xyaxis.line",
            description: Text("BattSignal saves a reading every 15 minutes. Try a longer range or check back later.")
        )
    }

    private func trendCaption(_ trend: WearTrend?) -> String {
        guard let trend else { return "Not enough cycles for a trend yet" }
        let change = -trend.lossPer100Cycles
        if abs(change) < 0.05 { return "0.0 % per 100 cycles" }
        return String(format: "%+.1f %% per 100 cycles", change)
    }

    private func tooltip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).fontWeight(.semibold).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func valueText(_ value: Double, metric: HistoryMetric) -> String {
        switch metric {
        case .health: String(format: "Health %.1f %%", value)
        case .cycles: "\(Int(value).formatted()) cycles"
        }
    }

    private func yDomain(_ values: [Double], metric: HistoryMetric) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        switch metric {
        case .health: return (floor(low) - 2)...(ceil(high) + 2)
        case .cycles: return max(0, low - 5)...(high + 5)
        }
    }
}

enum ChartKind: String, CaseIterable, Identifiable {
    case health = "Health"
    case cycles = "Cycles"
    case wear = "Health vs cycles"

    var id: Self { self }

    var metric: HistoryMetric? {
        switch self {
        case .health: .health
        case .cycles: .cycles
        case .wear: nil
        }
    }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case month = "30 days"
    case year = "1 year"
    case all = "All"

    var id: Self { self }

    var since: Date? {
        switch self {
        case .month: .now.addingTimeInterval(-30 * 86_400)
        case .year: .now.addingTimeInterval(-365 * 86_400)
        case .all: nil
        }
    }
}

extension Color {
    static let mustard = Color(red: 0.86, green: 0.66, blue: 0.13)
}
