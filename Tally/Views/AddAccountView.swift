import SwiftUI
import SwiftData

struct AddAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: AccountKind = .cash
    @State private var amountText = ""
    @State private var notes = ""

    private var parsedAmount: Decimal? { CurrencyFormat.parse(amountText) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedAmount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name"), text: $name)
                    Picker(String(localized: "Kind"), selection: $kind) {
                        ForEach(AccountKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                }

                Section {
                    TextField(String(localized: "Current value"), text: $amountText)
                        .keyboardType(.decimalPad)
                } footer: {
                    if kind.isLiability {
                        Text(String(localized: "Enter what you owe as a positive number."))
                    }
                }

                Section(String(localized: "Notes")) {
                    TextField(String(localized: "Optional"), text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(String(localized: "New account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save"), action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let account = Account(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(account)
        _ = account.record(amount)
        dismiss()
    }
}

#Preview {
    AddAccountView()
        .modelContainer(for: [Account.self, ValueSnapshot.self], inMemory: true)
}
