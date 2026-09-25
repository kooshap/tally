import SwiftData
import SwiftUI

/// Adds or edits one balance. Saving onto a day that already has an entry
/// overwrites it — the one-per-day rule lives in `BalanceStore.record`.
struct BalanceEntryEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var form: BalanceEntryForm

    init(account: Account, entry: BalanceEntry?) {
        _form = State(initialValue: BalanceEntryForm(account: account, entry: entry))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount in \(form.account.currencyCode)", text: $form.amountText)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("entry.amountField")

                    DatePicker(
                        "Date",
                        selection: $form.date,
                        in: BalanceStore.allowedDates(),
                        displayedComponents: .date
                    )
                    .disabled(form.entry != nil)
                } footer: {
                    switch form.notice {
                    case .dateIsFixed:
                        Text("An entry's date can't be changed. Delete it and add another to move it.")
                    case .replacesThatDaysBalance:
                        Text("This replaces the balance already recorded for that day.")
                    case .negativeNotAllowed:
                        Text("Only a bank account can hold a negative balance. Debts are entered as positive amounts.")
                    case nil:
                        EmptyView()
                    }
                }
            }
            .navigationTitle(form.entry == nil ? "Add balance" : "Edit balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!form.canSave)
                        .accessibilityIdentifier("entry.saveButton")
                }
            }
        }
    }

    private func save() {
        form.save(in: modelContext)
        dismiss()
    }
}
