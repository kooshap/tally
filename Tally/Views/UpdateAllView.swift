import SwiftData
import SwiftUI

/// §6: the monthly action. Steps through every active account with the last
/// known figure pre-filled, lets each one be edited or skipped, and writes
/// every entry under a single date.
struct UpdateAllView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var run: UpdateAllRun
    @State private var saveFailed = false

    init(accounts: [Account]) {
        _run = State(initialValue: UpdateAllRun(accounts: accounts))
    }

    var body: some View {
        NavigationStack {
            Group {
                if run.accounts.isEmpty {
                    ContentUnavailableView(
                        "No active accounts",
                        systemImage: "tray",
                        description: Text("Add an account before running an update.")
                    )
                } else if run.isReviewing {
                    reviewStep
                } else {
                    accountStep
                }
            }
            .navigationTitle(run.isReviewing ? "Review" : "Update balances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .saveFailedAlert(isPresented: $saveFailed)
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var accountStep: some View {
        if let account = run.current {
            Form {
                Section {
                    DatePicker(
                        "As of",
                        selection: $run.date,
                        in: BalanceStore.allowedDates(),
                        displayedComponents: .date
                    )
                    .disabled(run.isDateFixed)
                } footer: {
                    if run.isDateFixed {
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
                    TextField("Amount in \(account.currencyCode)", text: $run[draftFor: account.id])
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("updateAll.amountField")
                } header: {
                    // The explicit specifier keeps Xcode's string export from
                    // keying this as "%@", which the catalog doesn't translate.
                    Text("Account \(run.index + 1, specifier: "%lld") of \(run.accounts.count, specifier: "%lld")")
                } footer: {
                    if run.isNegativeAndDisallowed(account) {
                        Text("Only a bank account can hold a negative balance. Debts are entered as positive amounts.")
                    }
                }

                Section {
                    Button("Next") { run.next() }
                        .disabled(run.isNegativeAndDisallowed(account))
                        .accessibilityIdentifier("updateAll.nextButton")
                    Button("Skip this account") { run.skip() }
                        .accessibilityIdentifier("updateAll.skipButton")
                    if run.canGoBack {
                        Button("Back") { run.back() }
                    }
                }
            }
        }
    }

    private var reviewStep: some View {
        Form {
            Section {
                LabeledContent("Date") {
                    Text(run.date.formatted(.dateTime.day().month(.abbreviated).year()))
                }
            }

            Section("Will be saved") {
                ForEach(run.accountsToSave) { account in
                    LabeledContent(account.name) {
                        Text(run.draftText(for: account))
                            .monospacedDigit()
                    }
                }
            }

            if !run.accountsLeftOut.isEmpty {
                Section("Skipped") {
                    ForEach(run.accountsLeftOut) { account in
                        Text(account.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Save all", action: save)
                    .accessibilityIdentifier("updateAll.saveButton")
                Button("Back") { run.back() }
            }
        }
    }

    private func lastKnownText(for account: Account) -> String {
        guard let latest = account.latestEntry else { return String(localized: "None yet") }
        return MoneyFormatting.string(latest.amount, code: account.currencyCode)
    }

    private func save() {
        run.save(in: modelContext)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
