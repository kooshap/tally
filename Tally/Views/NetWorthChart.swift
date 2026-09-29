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
        let type: AccountType
        let amount: Double
    }

    private var slices: [Slice] {
        points.flatMap { point in
            AccountType.allCases.compactMap { type in
                guard let amount = point.totalsByType[type], amount != 0 else { return nil }
                return Slice(
                    id: "\(point.day.rawValue)-\(type.rawValue)",
                    date: point.day.date(),
                    type: type,
                    amount: amount.plotted
                )
            }
        }
    }

    /// The types on the chart, in the fixed order, so each keeps its colour
    /// and the legend lists only what is drawn.
    private func shownTypes(in slices: [Slice]) -> [AccountType] {
        let present = Set(slices.map(\.type))
        return AccountType.allCases.filter(present.contains)
    }

    var body: some View {
        let slices = slices
        let shownTypes = shownTypes(in: slices)
        Chart {
            ForEach(slices) { slice in
                AreaMark(
                    x: .value("Date", slice.date),
                    y: .value("Value", slice.amount)
                )
                .foregroundStyle(by: .value("Type", slice.type.localizedName))
                .interpolationMethod(.monotone)
            }

            if let selectedDay {
                RuleMark(x: .value("Selected", selectedDay.date()))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartForegroundStyleScale(
            domain: shownTypes.map(\.localizedName),
            range: shownTypes.map(\.chartColor)
        )
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

extension AccountType {
    /// Fixed per type, so a type keeps its colour whichever others are on the
    /// chart. Debt is red, as money owed.
    fileprivate var chartColor: Color {
        switch self {
        case .bank: return .blue
        case .broker: return .purple
        case .realEstate: return .orange
        case .debt: return .red
        }
    }
}
