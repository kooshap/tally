import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.createdAt, order: .reverse) private var accounts: [Account]
    @State private var isAddingAccount = false

    private var summary: NetWorthSummary { NetWorthSummary(accounts: accounts) }
    private var assets: [Account] { accounts.filter { !$0.kind.isLiability } }
    private var liabilities: [Account] { accounts.filter { $0.kind.isLiability } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NetWorthHeader(summary: summary)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if accounts.isEmpty {
                    Section {
                        EmptyStateView { isAddingAccount = true }
                            .listRowBackground(Color.clear)
                    }
                }

                accountSection(title: String(localized: "Assets"), accounts: assets)
                accountSection(title: String(localized: "Liabilities"), accounts: liabilities)
            }
            .navigationTitle(String(localized: "Tally"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingAccount = true
                    } label: {
                        Label(String(localized: "Add account"), systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingAccount) {
                AddAccountView()
            }
        }
    }

    @ViewBuilder
    private func accountSection(title: String, accounts: [Account]) -> some View {
        if !accounts.isEmpty {
            Section(title) {
                ForEach(accounts) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountRow(account: account)
                    }
                }
                .onDelete { offsets in
                    delete(offsets, from: accounts)
                }
            }
        }
    }

    private func delete(_ offsets: IndexSet, from source: [Account]) {
        for index in offsets {
            modelContext.delete(source[index])
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Account.self, ValueSnapshot.self], inMemory: true)
}
