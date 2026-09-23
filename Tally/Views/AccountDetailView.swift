import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var modelContext
    @State private var isRecordingValue = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CurrencyFormat.string(account.currentValue))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let latest = account.latestSnapshot {
                        Text(latest.recordedAt, format: .dateTime.day().month().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField(String(localized: "Name"), text: $account.name)
                Picker(String(localized: "Kind"), selection: $account.kind) {
                    ForEach(AccountKind.allCases) { kind in
                        Label(kind.label, systemImage: kind.symbolName).tag(kind)
                    }
                }
                TextField(String(localized: "Notes"), text: $account.notes, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section(String(localized: "History")) {
                ForEach(account.history.reversed()) { snapshot in
                    HStack {
                        Text(snapshot.recordedAt, format: .dateTime.day().month().year())
                        Spacer()
                        Text(CurrencyFormat.string(snapshot.amount))
                            .monospacedDigit()
                    }
                }
                .onDelete(perform: deleteSnapshots)

                Button(String(localized: "Record new value")) {
                    isRecordingValue = true
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isRecordingValue) {
            RecordValueView(account: account)
                .presentationDetents([.medium])
        }
    }

    private func deleteSnapshots(_ offsets: IndexSet) {
        let newestFirst = account.history.reversed().map { $0 }
        for index in offsets {
            modelContext.delete(newestFirst[index])
        }
    }
}
