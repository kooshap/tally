import SwiftUI
import SwiftData

/// §6: the monthly action. Steps through every active account with the last
/// known figure pre-filled, lets each one be edited or skipped, and writes
/// every entry under a single date.
struct UpdateAllView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let accounts: [Account]

    @State private var date = Date.now
    @State private var index = 0
    /// Keyed by account id: what will be written when the run is saved.
    @State private var drafts: [UUID: String] = [:]
    @State private var skipped: Set<UUID> = []
    @State private var isReviewing = false

    private var day: CalendarDay { CalendarDay(date: date) }
    private var current: Account? {
        accounts.indices.contains(index) ? accounts[index] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    ContentUnavailableView(
                        "No active accounts",
                        systemImage: "tray",
                        description: Text("Add an account before running an update.")
                    )
                } else if isReviewing {
                    reviewStep
                } else {
                    accountStep
                }
            }
            .navigationTitle(isReviewing ? "Review" : "Update balances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var accountStep: some View {
        if let account = current {
            Form {
                Section {
                    DatePicker("As of", selection: $date, in: BalanceStore.allowedDates(), displayedComponents: .date)
                        .disabled(index > 0)
                } footer: {
                    if index > 0 {
                        Text("Every balance in this run is saved under the same date.")
                    }
                }

                Section {
                    LabeledContent("Account") {
                        Text(account.name)
                    }
                    LabeledContent("Last known") {
                        Text(lastKnownText(for: account))
                            .foregroundStyle(.secondary)
                    }
                    TextField(
                        "Amount in \(account.currencyCode)",
                        text: Binding(
                            get: { drafts[account.id] ?? "" },
                            set: { drafts[account.id] = $0 }
                        )
                    )
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("updateAll.amountField")
                } header: {
                    Text("Account \(index + 1) of \(accounts.count)")
                }

                Section {
                    Button("Next") { advance() }
                        .accessibilityIdentifier("updateAll.nextButton")
                    Button("Skip this account") {
                        skipped.insert(account.id)
                        advance()
                    }
                    .accessibilityIdentifier("updateAll.skipButton")
                    if index > 0 {
                        Button("Back") { index -= 1 }
                    }
                }
            }
        }
    }

    private var reviewStep: some View {
        Form {
            Section {
                LabeledContent("Date") {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                }
            }

            Section("Will be saved") {
                ForEach(accounts.filter { willSave($0) }) { account in
                    LabeledContent(account.name) {
                        Text(draftText(for: account))
                            .monospacedDigit()
                    }
                }
            }

            if accounts.contains(where: { !willSave($0) }) {
                Section("Skipped") {
                    ForEach(accounts.filter { !willSave($0) }) { account in
                        Text(account.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Save all") { saveAll() }
                    .accessibilityIdentifier("updateAll.saveButton")
                Button("Back") { isReviewing = false }
            }
        }
    }

    // MARK: - Behaviour

    /// Pre-fills each field with the account's last known value, so an
    /// unchanged account is one tap.
    private func prefill() {
        for account in accounts where drafts[account.id] == nil {
            guard let latest = account.latestEntry else { continue }
            drafts[account.id] = MoneyFormatting.editableString(latest.amount)
        }
    }

    private func advance() {
        if index + 1 < accounts.count {
            index += 1
        } else {
            isReviewing = true
        }
    }

    private func lastKnownText(for account: Account) -> String {
        guard let latest = account.latestEntry else { return String(localized: "None yet") }
        return MoneyFormatting.string(latest.amount, code: account.currencyCode)
    }

    private func amount(for account: Account) -> Decimal? {
        MoneyFormatting.parse(drafts[account.id] ?? "", code: account.currencyCode)
    }

    private func willSave(_ account: Account) -> Bool {
        !skipped.contains(account.id) && amount(for: account) != nil
    }

    private func draftText(for account: Account) -> String {
        guard let amount = amount(for: account) else { return "—" }
        return MoneyFormatting.string(amount, code: account.currencyCode)
    }

    private func saveAll() {
        for account in accounts where willSave(account) {
            guard let amount = amount(for: account) else { continue }
            BalanceStore.record(amount, on: day, for: account, in: modelContext)
        }
        dismiss()
    }
}
