import SwiftUI

struct NetWorthHeader: View {
    let summary: NetWorthSummary

    var body: some View {
        VStack(spacing: 8) {
            Text(String(localized: "Net worth"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(CurrencyFormat.string(summary.net))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(summary.net < 0 ? Color.red : Color.primary)

            HStack(spacing: 24) {
                column(title: String(localized: "Assets"), value: summary.assets)
                column(title: String(localized: "Liabilities"), value: summary.liabilities)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func column(title: String, value: Decimal) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CurrencyFormat.string(value))
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
    }
}

#Preview {
    NetWorthHeader(summary: NetWorthSummary(assets: 182_400, liabilities: 46_900))
}
