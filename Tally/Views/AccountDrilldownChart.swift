import Charts
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

    @State private var showInBaseCurrency = false

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

    private struct Sample: Identifiable {
        let id: Int
        let date: Date
        let amount: Double
    }

    private var samples: [Sample] {
        guard let account = selectedAccount else { return [] }
        return account.sortedEntries.compactMap { entry in
            let amount: Decimal?
            if showInBaseCurrency && isForeign {
                amount = rates.convert(
                    entry.amount,
                    from: account.currencyCode,
                    to: baseCurrency,
                    on: entry.day
                )
            } else {
                amount = entry.amount
            }
            guard let amount else { return nil }
            return Sample(id: entry.dayNumber, date: entry.day.date(), amount: amount.plotted)
        }
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

            if samples.isEmpty {
                Text("This account has no balances yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 240)
            } else {
                Chart(samples) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Value", sample.amount)
                    )
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", sample.date),
                        y: .value("Value", sample.amount)
                    )
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(MoneyFormatting.compact(Decimal(amount), code: displayCurrency))
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
        }
    }
}
