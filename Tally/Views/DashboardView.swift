import SwiftData
import SwiftUI

enum ChartMode: String, CaseIterable, Identifiable {
    case total
    case byType
    case perAccount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .total: return String(localized: "Total")
        case .byType: return String(localized: "By type")
        case .perAccount: return String(localized: "Per account")
        }
    }
}

/// The series is computed here and the chart selection lives in
/// `DashboardContent`, so a drag across the chart, which changes `selectedDay`
/// on every frame, re-runs only the child. This body reads just the accounts
/// and their entries, the rate table, and the base currency, and Observation
/// re-runs it when any of them changes, so a new balance still shows up. A
/// series cached in `@State` would need a key covering every entry's day and
/// amount, and would go stale the day the calculator reads something the key
/// leaves out.
struct DashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RatesCoordinator.self) private var rates

    // Archived accounts stay in the query: their history remains on the graph.
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    var body: some View {
        NavigationStack {
            DashboardContent(
                series: NetWorthCalculator.series(
                    ledgers: accounts.map(\.ledger),
                    rates: rates.table,
                    baseCurrency: settings.baseCurrency
                ),
                accounts: accounts
            )
        }
    }
}

private struct DashboardContent: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RatesCoordinator.self) private var rates
    @Environment(\.modelContext) private var modelContext

    let series: [NetWorthPoint]
    let accounts: [Account]

    @State private var mode: ChartMode = .total
    @State private var range: ChartRange = .oneYear
    @State private var selectedDay: CalendarDay?
    @State private var drilldownAccountID: UUID?

    private var plottable: [NetWorthPoint] {
        series.filter(\.hasCompleteRates)
    }

    private var pointsMissingRates: [NetWorthPoint] {
        series.filter { !$0.hasCompleteRates }
    }

    var body: some View {
        let today = CalendarDay.today()
        let offeredRanges = ChartRange.offered(for: plottable.map(\.day), today: today)
        let shownRange = offeredRanges.contains(range) ? range : .all
        let window = plottable.filter { shownRange.includes($0.day, today: today) }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headline(window: window)

                if !pointsMissingRates.isEmpty {
                    MissingRatesBanner(points: pointsMissingRates) {
                        Task {
                            await rates.backfillHistory(context: modelContext, settings: settings)
                        }
                    }
                }

                if series.isEmpty {
                    DashboardEmptyState()
                } else {
                    Picker("Chart", selection: $mode) {
                        ForEach(ChartMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    chart(window: window, range: shownRange)

                    if offeredRanges.count > 1 {
                        Picker("Range", selection: $range) {
                            ForEach(offeredRanges) { range in
                                Text(range.shortLabel)
                                    .accessibilityLabel(range.spokenLabel)
                                    .tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Net worth")
        .onChange(of: range) { selectedDay = nil }
        .onChange(of: mode) { selectedDay = nil }
    }

    /// Today's net worth, or the selected day's while dragging, with the
    /// change since the first point in the chart's range.
    @ViewBuilder
    private func headline(window: [NetWorthPoint]) -> some View {
        let selected = selectedDay.flatMap { day in window.first { $0.day == day } }
        let shown = selected ?? series.last

        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let selected {
                    Text("On \(dayText(selected.day))")
                } else {
                    Text("Today")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(shown?.total.map { MoneyFormatting.string($0, code: settings.baseCurrency) } ?? "—")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            if window.count > 1, let start = window.first, let startTotal = start.total, let shownTotal = shown?.total {
                let change = NetWorthCalculator.change(from: startTotal, to: shownTotal)
                HStack(spacing: 4) {
                    Image(systemName: change.amount < 0 ? "arrow.down.right" : "arrow.up.right")
                        .accessibilityHidden(true)
                    Text(verbatim: changeText(change))
                        .monospacedDigit()
                    Text("since \(dayText(start.day))")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(change.amount < 0 ? .red : .green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayText(_ day: CalendarDay) -> String {
        day.date().formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func changeText(_ change: (amount: Decimal, fraction: Decimal?)) -> String {
        let amount = MoneyFormatting.signedChange(change.amount, code: settings.baseCurrency)
        guard let fraction = change.fraction else { return amount }
        return "\(amount) (\(MoneyFormatting.percent(fraction)))"
    }

    @ViewBuilder
    private func chart(window: [NetWorthPoint], range: ChartRange) -> some View {
        switch mode {
        case .total:
            NetWorthChart(points: window, baseCurrency: settings.baseCurrency, selectedDay: $selectedDay)
        case .byType:
            BreakdownChart(points: window, baseCurrency: settings.baseCurrency, selectedDay: $selectedDay)
        case .perAccount:
            AccountDrilldownChart(
                accounts: accounts,
                selectedAccountID: $drilldownAccountID,
                rates: rates.table,
                baseCurrency: settings.baseCurrency,
                range: range
            )
        }
    }
}

private struct DashboardEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No balances yet")
                .font(.headline)
            Text("Add an account and enter what it's worth. The chart starts from your first entry.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// §4: points without rates are excluded from the chart and explained, never
/// drawn at a guessed value.
private struct MissingRatesBanner: View {
    let points: [NetWorthPoint]
    let onRetry: () -> Void

    private var currencies: String {
        Set(points.flatMap(\.missingCurrencies)).sorted().joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Some days can't be shown", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.medium))

            // See UpdateAllView: the explicit specifier keeps the exported key "%lld".
            Text(
                "^[\(points.count, specifier: "%lld") day](inflect: true) have no exchange rate for \(currencies), so they're left off the chart rather than estimated."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button("Download rates", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}
