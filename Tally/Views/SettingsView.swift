import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RatesCoordinator.self) private var rates
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Picker("Portfolio currency", selection: $settings.baseCurrency) {
                        ForEach(CurrencyCatalog.all, id: \.self) { code in
                            Text(CurrencyCatalog.displayName(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text(
                        "Changing this re-converts your whole history using the rates that applied on each day. Nothing is lost."
                    )
                }

                Section {
                    Toggle("Require Face ID or passcode", isOn: $settings.faceIDEnabled)
                        .disabled(!AppLock.isAvailable)
                } footer: {
                    if AppLock.isAvailable {
                        Text("Locks Tally when you leave it, and hides your balances in the app switcher.")
                    } else {
                        Text("Set a passcode on this iPhone to use this.")
                    }
                }

                Section("Exchange rates") {
                    LabeledContent("Rates as of") {
                        Text(ratesAsOfText)
                            .foregroundStyle(.secondary)
                    }

                    if case .failed(let message) = rates.status {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await rates.refresh(.ninetyDays, context: modelContext, settings: settings) }
                    } label: {
                        if rates.status == .refreshing {
                            HStack {
                                ProgressView()
                                Text("Refreshing…")
                            }
                        } else {
                            Text("Refresh now")
                        }
                    }
                    .disabled(rates.status == .refreshing)

                    Button("Download full history") {
                        Task { await rates.backfillHistory(context: modelContext, settings: settings) }
                    }
                    .disabled(rates.status == .refreshing)
                }

                Section {
                    NavigationLink("About Tally") { AboutView() }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var ratesAsOfText: String {
        guard let day = rates.table.latestDay else { return String(localized: "Not downloaded yet") }
        return day.date().formatted(.dateTime.day().month(.abbreviated).year())
    }
}
