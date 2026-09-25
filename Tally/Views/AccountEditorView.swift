import SwiftData
import SwiftUI

/// Creates a new account or edits an existing one's identity fields.
struct AccountEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]

    @State private var form: AccountForm

    /// `nil` creates; otherwise edits in place.
    init(account: Account?) {
        _form = State(initialValue: AccountForm(editing: account))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $form.name)
                        .accessibilityIdentifier("account.nameField")

                    Picker("Type", selection: $form.type) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.localizedName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .disabled(form.isCurrencyAndTypeLocked)

                    Picker("Currency", selection: $form.currencyCode) {
                        ForEach(CurrencyCatalog.all, id: \.self) { code in
                            Text(CurrencyCatalog.displayName(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(form.isCurrencyAndTypeLocked)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if form.isCurrencyAndTypeLocked {
                            Text(
                                "Currency and type can't change once an account has balances. To change them, archive this account and start a new one."
                            )
                            .accessibilityIdentifier("account.lockedFooter")
                        }
                        if form.type == .debt {
                            Text("Enter what you owe as a positive number. Tally subtracts it from your net worth.")
                        }
                    }
                }

                if !form.isEditing {
                    Section {
                        TextField("Opening balance (optional)", text: $form.openingBalance)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("account.openingBalanceField")
                    } footer: {
                        if form.isOpeningBalanceNegativeAndDisallowed {
                            Text(
                                "Only a bank account can hold a negative balance. Debts are entered as positive amounts."
                            )
                        } else {
                            Text("Saved as today's balance. You can backfill older figures afterwards.")
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $form.notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(form.isEditing ? "Edit account" : "New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!form.canSave)
                        .accessibilityIdentifier("account.saveButton")
                }
            }
            .onAppear { form.useCurrencyIfUnset(settings.baseCurrency) }
        }
    }

    private func save() {
        form.save(after: allAccounts, in: modelContext)
        dismiss()
    }
}
