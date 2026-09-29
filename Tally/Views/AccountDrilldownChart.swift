import SwiftUI

/// Mode 3: one account's line, in its own currency, with a toggle for the
/// portfolio currency.
///
/// The toggle matters for a foreign-currency account: in its own currency the
/// line shows what you did, while in the base currency it also carries what the
/// exchange rate did. Seeing them apart is the point.
struct AccountDrilldownChart: View {
    let accounts: [Account]
    @Binding var selectedAccountID: UUID?
    let rates: RateTable
    let baseCurrency: String
    let range: ChartRange

    @State private var showInBaseCurrency = false
    @State private var selectedDay: CalendarDay?

    private var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID } ?? accounts.first
    }

    private var isForeign: Bool {
        guard let selectedAccount else { return false }
        return selectedAccount.currencyCode != baseCurrency
    }

    private var displayCurrency: String {
        guard let selectedAccount else { return baseCurrency }
        return (showInBaseCurrency && isForeign) ? baseCurrency : selectedAccount.currencyCode
    }

    private var samples: [TrendLineChart.Sample] {
        guard let account = selectedAccount else { return [] }
        let today = CalendarDay.today()
        return account.ledger.history(convertedTo: displayCurrency, using: rates)
            .filter { range.includes($0.day, today: today) }
            .map { TrendLineChart.Sample(day: $0.day, amount: $0.amount) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                "Account",
                selection: Binding(
                    get: { selectedAccount?.id },
                    set: { selectedAccountID = $0 }
                )
            ) {
                ForEach(accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            .pickerStyle(.menu)

            if isForeign {
                Toggle("Show in \(baseCurrency)", isOn: $showInBaseCurrency)
                    .font(.subheadline)
            }

            let samples = samples
            if samples.isEmpty {
                Text(
                    range == .all ? "This account has no balances yet." : "This account has no balances in this period."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(height: 220)
            } else {
                readout(samples)

                TrendLineChart(
                    samples: samples,
                    upIsGood: selectedAccount?.type.isLiability != true,
                    selectedDay: $selectedDay
                )
            }
        }
    }

    /// The account's own figure: the selected day's while dragging, else its
    /// latest balance in the range.
    private func readout(_ samples: [TrendLineChart.Sample]) -> some View {
        let shown = selectedDay.flatMap { day in samples.first { $0.day == day } } ?? samples.last
        return VStack(alignment: .leading, spacing: 2) {
            Text(shown.map { MoneyFormatting.string($0.amount, code: displayCurrency) } ?? "—")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(shown.map { $0.day.date().formatted(.dateTime.day().month(.abbreviated).year()) } ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
