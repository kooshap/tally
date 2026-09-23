import SwiftUI

struct RecordValueView: View {
    let account: Account
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var date = Date.now

    private var parsedAmount: Decimal? { CurrencyFormat.parse(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Value"), text: $amountText)
                    .keyboardType(.decimalPad)
                DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
            }
            .navigationTitle(String(localized: "Record value"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        if let amount = parsedAmount {
                            _ = account.record(amount, on: date)
                        }
                        dismiss()
                    }
                    .disabled(parsedAmount == nil)
                }
            }
        }
    }
}
