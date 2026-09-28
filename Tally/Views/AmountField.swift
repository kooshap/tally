import SwiftUI
import UIKit

/// An amount typed in one currency: the code stays beside the figure the whole
/// time, and the digits are grouped as they go in so a six-figure balance can
/// be read back at a glance.
struct AmountField: View {
    let title: LocalizedStringResource
    @Binding var text: String
    let currencyCode: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            GroupingTextField(
                placeholder: String(localized: title),
                accessibilityLabel: String(localized: "Amount in \(currencyCode)"),
                accessibilityIdentifier: accessibilityIdentifier,
                text: $text
            )
            Text(currencyCode)
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }
}

/// A UIKit field, because regrouping has to happen inside the keystroke.
/// SwiftUI's `TextField` only reports an edit after UIKit has applied it, so
/// rewriting the text from there races the next keystroke: a quick run of
/// deletes lost some of them to the rewrite of the one before.
private struct GroupingTextField: UIViewRepresentable {
    let placeholder: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numbersAndPunctuation
        field.autocorrectionType = .no
        field.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .regular))
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        field.placeholder = placeholder
        field.accessibilityLabel = accessibilityLabel
        field.accessibilityIdentifier = accessibilityIdentifier
        // Only when the text changed elsewhere, such as the update-all run
        // moving to the next account; writing it back unchanged would move
        // the cursor.
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textField(
            _ field: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString replacement: String
        ) -> Bool {
            let current = field.text ?? ""
            guard field.markedTextRange == nil, let bounds = Range(range, in: current) else { return true }

            let edit = MoneyFormatting.applyingEdit(
                to: current,
                replacing: current.distance(
                    from: current.startIndex, to: bounds.lowerBound)..<current.distance(
                        from: current.startIndex, to: bounds.upperBound),
                with: replacement
            )
            field.text = edit.text
            let caret = edit.text.index(edit.text.startIndex, offsetBy: edit.caret).utf16Offset(in: edit.text)
            if let position = field.position(from: field.beginningOfDocument, offset: caret) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            text.wrappedValue = edit.text
            return false
        }

        /// Return dismisses the keyboard, as it does for SwiftUI's fields.
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
        }
    }
}
