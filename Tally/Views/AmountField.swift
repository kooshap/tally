import SwiftUI

/// An amount typed in one currency: the code stays beside the figure the whole
/// time, and the digits are grouped as they go in so a six-figure balance can
/// be read back at a glance.
struct AmountField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let currencyCode: String

    @State private var selection: TextSelection?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TextField(title, text: $text, selection: $selection)
                .keyboardType(.numbersAndPunctuation)
                .monospacedDigit()
                .accessibilityLabel(Text("Amount in \(currencyCode)"))
            Text(currencyCode)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .onChange(of: text) { _, typed in regroup(typed) }
    }

    private func regroup(_ typed: String) {
        let caret: Int
        if case .selection(let range) = selection?.indices, range.isEmpty, range.lowerBound <= typed.endIndex {
            caret = typed.distance(from: typed.startIndex, to: range.lowerBound)
        } else {
            caret = typed.count
        }
        let regrouped = MoneyFormatting.regroupedForTyping(typed, caret: caret)
        guard regrouped.text != typed else { return }
        text = regrouped.text
        selection = TextSelection(
            insertionPoint: regrouped.text.index(regrouped.text.startIndex, offsetBy: regrouped.caret)
        )
    }
}
