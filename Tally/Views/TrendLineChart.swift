import Charts
import SwiftUI

/// A line in the style of a stock app, for the total and for one account.
///
/// There are no axes, and the scale is fitted to the values rather than
/// starting at zero, so a month's movement shows instead of being squeezed
/// into the top of the chart. The line is green when the range ended better
/// than it began and red when it ended worse. Dragging marks the day under the
/// finger, fades the line after it, and gives a haptic tick on each day with a
/// balance. The caller shows the selected day's figures.
struct TrendLineChart: View {
    struct Sample: Identifiable {
        let day: CalendarDay
        let amount: Decimal

        var id: Int { day.rawValue }
    }

    /// Oldest first.
    let samples: [Sample]
    /// False for a debt, where a falling line is the good news.
    var upIsGood = true
    @Binding var selectedDay: CalendarDay?

    @State private var selectedDate: Date?

    private var tint: Color {
        guard let first = samples.first?.amount, let last = samples.last?.amount else { return .accentColor }
        let improved = upIsGood ? last >= first : last <= first
        return improved ? .green : .red
    }

    private var selected: Sample? {
        selectedDay.flatMap { day in samples.first { $0.day == day } }
    }

    /// Fitted to the values with a margin, so the line never touches the edge.
    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.amount.plotted)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let margin = high > low ? (high - low) * 0.12 : max(abs(high) * 0.05, 1)
        return (low - margin)...(high + margin)
    }

    var body: some View {
        let yDomain = yDomain
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Date", sample.day.date()),
                    yStart: .value("Floor", yDomain.lowerBound),
                    yEnd: .value("Value", sample.amount.plotted)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    .linearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", sample.day.date()),
                    y: .value("Value", sample.amount.plotted)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(lineStyle)
            }

            // A single balance draws no line, so it gets a dot.
            if samples.count == 1, let only = samples.first {
                PointMark(
                    x: .value("Date", only.day.date()),
                    y: .value("Value", only.amount.plotted)
                )
                .foregroundStyle(tint)
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.day.date()))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Date", selected.day.date()),
                    y: .value("Value", selected.amount.plotted)
                )
                .symbol {
                    Circle()
                        .fill(tint)
                        .stroke(.background, lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartXSelection(value: $selectedDate)
        .frame(height: 220)
        .onChange(of: selectedDate) { _, date in
            selectedDay = date.flatMap(nearest(to:))?.day
        }
        .sensoryFeedback(.selection, trigger: selectedDay) { _, day in day != nil }
    }

    /// From the first balance to the last, with no padding either side, so the
    /// line runs edge to edge.
    private var xDomain: ClosedRange<Date> {
        guard let first = samples.first?.day.date(), let last = samples.last?.day.date(), first < last else {
            let only = samples.first?.day.date() ?? .now
            return only.addingTimeInterval(-86_400)...only.addingTimeInterval(86_400)
        }
        return first...last
    }

    /// Past the selection the line fades, so the part up to the finger reads
    /// as the history that led to the selected figure.
    private var lineStyle: AnyShapeStyle {
        guard let selected, samples.count > 1 else { return AnyShapeStyle(tint) }
        let span = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        let fraction = selected.day.date().timeIntervalSince(xDomain.lowerBound) / span
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: tint, location: fraction),
                    .init(color: tint.opacity(0.3), location: fraction),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    /// Selection lands on an arbitrary x; snap it to the nearest real point so
    /// the readout always shows a day that actually has data.
    private func nearest(to date: Date) -> Sample? {
        samples.min {
            abs($0.day.date().timeIntervalSince(date)) < abs($1.day.date().timeIntervalSince(date))
        }
    }
}
