import SwiftData
import SwiftUI

struct AccountsListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RatesCoordinator.self) private var rates
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var isAddingAccount = false
    @State private var isUpdatingAll = false
    @State private var showArchived = false

    private var active: [Account] { accounts.filter { !$0.isArchived } }
    private var archived: [Account] { accounts.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            List {
                if !active.isEmpty {
                    Section {
                        Button {
                            isUpdatingAll = true
                        } label: {
                            Label("Update all balances", systemImage: "arrow.clockwise")
                        }
                    } footer: {
                        Text("Steps through every account with last month's figures pre-filled.")
                    }
                }

                Section("Accounts") {
                    ForEach(active) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            AccountRow(account: account)
                        }
                    }
                    .onMove(perform: move)

                    if active.isEmpty {
                        Button("Add your first account") { isAddingAccount = true }
                    }
                }

                if !archived.isEmpty {
                    Section {
                        DisclosureGroup("Archived", isExpanded: $showArchived) {
                            ForEach(archived) { account in
                                NavigationLink {
                                    AccountDetailView(account: account)
                                } label: {
                                    AccountRow(account: account)
                                }
                            }
                        }
                    } footer: {
                        Text("Archived accounts stay on the chart for the period they existed.")
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingAccount = true
                    } label: {
                        Label("Add account", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $isAddingAccount) {
                AccountEditorView(account: nil)
            }
            .sheet(isPresented: $isUpdatingAll) {
                UpdateAllView(accounts: active)
            }
        }
    }

    private func move(_ offsets: IndexSet, to destination: Int) {
        var reordered = active
        reordered.move(fromOffsets: offsets, toOffset: destination)
        BalanceStore.reorder(reordered)
    }
}

struct AccountRow: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RatesCoordinator.self) private var rates
    let account: Account

    /// Shows the converted figure underneath when the account is in another
    /// currency, so the list adds up to the headline on screen.
    private var convertedText: String? {
        guard account.currencyCode != settings.baseCurrency,
            let entry = account.latestEntry,
            let converted = rates.convert(
                entry.amount,
                from: account.currencyCode,
                to: settings.baseCurrency,
                on: entry.day
            )
        else { return nil }
        return MoneyFormatting.string(converted, code: settings.baseCurrency)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.symbolName)
                .frame(width: 28, height: 28)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.type.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyFormatting.string(account.currentAmount, code: account.currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(account.type.isLiability ? .red : .primary)
                if let convertedText {
                    Text(convertedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

extension RatesCoordinator {
    fileprivate func convert(
        _ amount: Decimal,
        from source: String,
        to target: String,
        on day: CalendarDay
    ) -> Decimal? {
        table.convert(amount, from: source, to: target, on: day)
    }
}
