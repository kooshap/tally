import SwiftData
import SwiftUI

struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditingAccount = false
    @State private var entryBeingEdited: BalanceEntry?
    @State private var isAddingEntry = false
    @State private var isConfirmingDelete = false

    private var entriesNewestFirst: [BalanceEntry] {
        account.sortedEntries.reversed()
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MoneyFormatting.string(account.currentAmount, code: account.currencyCode))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let latest = account.latestEntry {
                        Text("Updated \(latest.day.date().formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if account.isArchived, let archivedOn = account.archivedOn {
                        Label(
                            "Archived on \(archivedOn.date().formatted(.dateTime.day().month(.abbreviated).year()))",
                            systemImage: "archivebox"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("History") {
                Button("Add a balance") { isAddingEntry = true }
                    .accessibilityIdentifier("detail.addEntryButton")

                ForEach(entriesNewestFirst) { entry in
                    Button {
                        entryBeingEdited = entry
                    } label: {
                        HStack {
                            Text(entry.day.date().formatted(.dateTime.day().month(.abbreviated).year()))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(MoneyFormatting.string(entry.amount, code: account.currencyCode))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteEntries)
            }

            Section {
                if account.isArchived {
                    Button("Unarchive") {
                        BalanceStore.unarchive(account, in: modelContext)
                    }
                } else {
                    Button("Archive") {
                        BalanceStore.archive(account, in: modelContext)
                    }
                }

                Button("Delete account", role: .destructive) {
                    isConfirmingDelete = true
                }
            } footer: {
                Text("Archiving keeps this account's past on the chart. Deleting removes it from history entirely.")
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditingAccount = true }
            }
        }
        .sheet(isPresented: $isEditingAccount) {
            AccountEditorView(account: account)
        }
        .sheet(isPresented: $isAddingEntry) {
            BalanceEntryEditor(account: account, entry: nil)
        }
        .sheet(item: $entryBeingEdited) { entry in
            BalanceEntryEditor(account: account, entry: entry)
        }
        .confirmationDialog(
            "Delete this account?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account and its history", role: .destructive) {
                BalanceStore.delete(account, in: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This rewrites your net worth history as though the account never existed. Archiving instead keeps the past intact."
            )
        }
    }

    private func deleteEntries(_ offsets: IndexSet) {
        let list = entriesNewestFirst
        for index in offsets {
            BalanceStore.delete(list[index], in: modelContext)
        }
    }
}
