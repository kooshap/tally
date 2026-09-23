import SwiftUI

struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.kind.symbolName)
                .font(.body)
                .frame(width: 28, height: 28)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.kind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(CurrencyFormat.string(account.currentValue))
                .monospacedDigit()
                .foregroundStyle(account.kind.isLiability ? Color.red : Color.primary)
        }
    }
}
