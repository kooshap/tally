import SwiftUI
import SwiftData

/// Creates a new account or edits an existing one's identity fields.
struct AccountEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]

    /// `nil` creates; otherwise edits in place.
    let account: Account?

    @State private var name = ""
    @State private var type: AccountType = .bank
    @State private var currencyCode = ""
    @State private var notes = ""
    @State private var openingBalance = ""

    private var isEditing: Bool { account != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedName.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("account.nameField")

                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.localizedName, systemImage: type.symbolName).tag(type)
                        }
                    }

                    Picker("Currency", selection: $currencyCode) {
                        ForEach(CurrencyCatalog.all, id: \.self) { code in
                            Text(CurrencyCatalog.displayName(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    if type == .debt {
                        Text("Enter what you owe as a positive number. Tally subtracts it from your net worth.")
                    }
                }

                if !isEditing {
                    Section {
                        TextField("Opening balance (optional)", text: $openingBalance)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("account.openingBalanceField")
                    } footer: {
                        Text("Saved as today's balance. You can backfill older figures afterwards.")
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(isEditing ? "Edit account" : "New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("account.saveButton")
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let account else {
            if currencyCode.isEmpty { currencyCode = settings.baseCurrency }
            return
        }
        name = account.name
        type = account.type
        currencyCode = account.currencyCode
        notes = account.notes ?? ""
    }

    private func save() {
        if let account {
            account.name = trimmedName
            account.type = type
            account.currencyCode = currencyCode
            account.notes = notes.isEmpty ? nil : notes
        } else {
            let new = Account(
                name: trimmedName,
                type: type,
                currencyCode: currencyCode,
                notes: notes.isEmpty ? nil : notes,
                sortOrder: (allAccounts.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(new)

            if let amount = MoneyFormatting.parse(openingBalance, code: currencyCode) {
                BalanceStore.record(amount, on: .today(), for: new, in: modelContext)
            }
        }
        dismiss()
    }
}
