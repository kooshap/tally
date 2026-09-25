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

struct DashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RatesCoordinator.self) private var rates
    @Environment(\.modelContext) private var modelContext

    // Archived accounts stay in the query: their history remains on the graph.
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var mode: ChartMode = .total
    @State private var selectedDay: CalendarDay?
    @State private var drilldownAccountID: UUID?

    private var series: [NetWorthPoint] {
        NetWorthCalculator.series(
            ledgers: accounts.map(\.ledger),
            rates: rates.table,
            baseCurrency: settings.baseCurrency
        )
    }

    private var plottable: [NetWorthPoint] {
        series.filter(\.hasCompleteRates)
    }

    private var pointsMissingRates: [NetWorthPoint] {
        series.filter { !$0.hasCompleteRates }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headline

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

                        chart
                    }
                }
                .padding()
            }
            .navigationTitle("Net worth")
        }
    }

    @ViewBuilder
    private var headline: some View {
        let summary = NetWorthCalculator.headline(series)

        VStack(alignment: .leading, spacing: 6) {
            Text(selectedDay == nil ? "Today" : "On \(selectedPointDayText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(headlineAmountText(summary))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            if selectedDay == nil, let change = summary?.change {
                Label {
                    Text(MoneyFormatting.signedChange(change, code: settings.baseCurrency))
                } icon: {
                    Image(systemName: change < 0 ? "arrow.down.right" : "arrow.up.right")
                }
                .font(.subheadline)
                .foregroundStyle(change < 0 ? .red : .green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedPointDayText: String {
        guard let selectedDay else { return "" }
        return selectedDay.date().formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func headlineAmountText(_ summary: (current: NetWorthPoint, change: Decimal?)?) -> String {
        let point = selectedDay.flatMap { day in series.first { $0.day == day } } ?? summary?.current
        guard let total = point?.total else { return "—" }
        return MoneyFormatting.string(total, code: settings.baseCurrency)
    }

    @ViewBuilder
    private var chart: some View {
        switch mode {
        case .total:
            NetWorthChart(points: plottable, baseCurrency: settings.baseCurrency, selectedDay: $selectedDay)
        case .byType:
            BreakdownChart(points: plottable, baseCurrency: settings.baseCurrency, selectedDay: $selectedDay)
        case .perAccount:
            AccountDrilldownChart(
                accounts: accounts,
                selectedAccountID: $drilldownAccountID,
                rates: rates.table,
                baseCurrency: settings.baseCurrency
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
