import Charts
import SwiftUI

/// Mode 1: total net worth as a line.
struct NetWorthChart: View {
    let points: [NetWorthPoint]
    let baseCurrency: String
    @Binding var selectedDay: CalendarDay?

    @State private var selectedDate: Date?

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.day.date()),
                y: .value("Net worth", (point.total ?? 0).plotted)
            )
            .interpolationMethod(.monotone)

            AreaMark(
                x: .value("Date", point.day.date()),
                y: .value("Net worth", (point.total ?? 0).plotted)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                .linearGradient(
                    colors: [.accentColor.opacity(0.28), .accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if let marked = selectedDate.flatMap(nearest(to:)) {
                RuleMark(x: .value("Selected", marked.day.date()))
                    .foregroundStyle(.secondary.opacity(0.4))
                PointMark(
                    x: .value("Date", marked.day.date()),
                    y: .value("Net worth", (marked.total ?? 0).plotted)
                )
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(MoneyFormatting.compact(Decimal(amount), code: baseCurrency))
                    }
                }
            }
        }
        .frame(height: 240)
        .onChange(of: selectedDate) { _, date in
            selectedDay = date.flatMap { nearest(to: $0)?.day }
        }
    }

    /// Selection lands on an arbitrary x; snap it to the nearest real point so
    /// the readout always shows a day that actually has data.
    private func nearest(to date: Date) -> NetWorthPoint? {
        points.min {
            abs($0.day.date().timeIntervalSince(date)) < abs($1.day.date().timeIntervalSince(date))
        }
    }
}

/// Mode 2: stacked area by account type, with debt below the axis.
struct BreakdownChart: View {
    let points: [NetWorthPoint]
    let baseCurrency: String
    @Binding var selectedDay: CalendarDay?

    @State private var selectedDate: Date?

    private struct Slice: Identifiable {
        let id: String
        let date: Date
        let typeName: String
        let amount: Double
    }

    private var slices: [Slice] {
        points.flatMap { point in
            AccountType.allCases.compactMap { type in
                guard let amount = point.totalsByType[type], amount != 0 else { return nil }
                return Slice(
                    id: "\(point.day.rawValue)-\(type.rawValue)",
                    date: point.day.date(),
                    typeName: type.localizedName,
                    amount: amount.plotted
                )
            }
        }
    }

    var body: some View {
        Chart(slices) { slice in
            AreaMark(
                x: .value("Date", slice.date),
                y: .value("Value", slice.amount)
            )
            .foregroundStyle(by: .value("Type", slice.typeName))
            .interpolationMethod(.monotone)
        }
        .chartXSelection(value: $selectedDate)
        .chartLegend(position: .bottom)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(MoneyFormatting.compact(Decimal(amount), code: baseCurrency))
                    }
                }
            }
        }
        .frame(height: 240)
        .onChange(of: selectedDate) { _, date in
            guard let date else {
                selectedDay = nil
                return
            }
            selectedDay =
                points.min {
                    abs($0.day.date().timeIntervalSince(date)) < abs($1.day.date().timeIntervalSince(date))
                }?.day
        }
    }
}
