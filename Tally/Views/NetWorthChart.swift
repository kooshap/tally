import Charts
import SwiftUI

/// Mode 1: total net worth as a line.
struct NetWorthChart: View {
    let points: [NetWorthPoint]
    @Binding var selectedDay: CalendarDay?

    var body: some View {
        TrendLineChart(
            samples: points.compactMap { point in
                point.total.map { TrendLineChart.Sample(day: point.day, amount: $0) }
            },
            selectedDay: $selectedDay
        )
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
        Chart {
            ForEach(slices) { slice in
                AreaMark(
                    x: .value("Date", slice.date),
                    y: .value("Value", slice.amount)
                )
                .foregroundStyle(by: .value("Type", slice.typeName))
                .interpolationMethod(.monotone)
            }

            if let selectedDay {
                RuleMark(x: .value("Selected", selectedDay.date()))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
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
        .sensoryFeedback(.selection, trigger: selectedDay) { _, day in day != nil }
    }
}
