import SwiftUI
import SwiftData

/// Adds or edits one balance. Saving onto a day that already has an entry
/// overwrites it — the one-per-day rule lives in `BalanceStore.record`.
struct BalanceEntryEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: Account
    let entry: BalanceEntry?

    @State private var amountText = ""
    @State private var date = Date.now

    private var parsedAmount: Decimal? {
        MoneyFormatting.parse(amountText, code: account.currencyCode)
    }

    private var day: CalendarDay { CalendarDay(date: date) }

    private var wouldOverwrite: Bool {
        guard entry == nil else { return false }
        return account.entries.contains { $0.dayNumber == day.rawValue }
    }

    private var isNegativeAndDisallowed: Bool {
        guard let parsedAmount else { return false }
        return parsedAmount < 0 && !account.type.allowsNegativeBalance
    }

    private var canSave: Bool {
        parsedAmount != nil && !isNegativeAndDisallowed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount in \(account.currencyCode)", text: $amountText)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("entry.amountField")

                    // §6: the past can be backfilled; the future cannot be known.
                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .disabled(entry != nil)
                } footer: {
                    if entry != nil {
                        Text("An entry's date can't be changed. Delete it and add another to move it.")
                    } else if wouldOverwrite {
                        Text("This replaces the balance already recorded for that day.")
                    } else if isNegativeAndDisallowed {
                        Text("Only a bank account can hold a negative balance. Debts are entered as positive amounts.")
                    }
                }
            }
            .navigationTitle(entry == nil ? "Add balance" : "Edit balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("entry.saveButton")
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let entry else { return }
        amountText = "\(entry.amount)"
        date = entry.day.date()
    }

    private func save() {
        guard let parsedAmount else { return }
        if let entry {
            entry.amount = parsedAmount
            entry.updatedAt = .now
        } else {
            BalanceStore.record(parsedAmount, on: day, for: account, in: modelContext)
        }
        dismiss()
    }
}
