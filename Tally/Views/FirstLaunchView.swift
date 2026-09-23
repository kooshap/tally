import SwiftUI

/// §3: the base currency is chosen at first launch. It is changeable later, and
/// changing it costs nothing, because history is stored euro-relative.
struct FirstLaunchView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selection: String = CurrencyCatalog.deviceDefault()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Portfolio currency", selection: $selection) {
                        ForEach(CurrencyCatalog.all, id: \.self) { code in
                            Text(CurrencyCatalog.displayName(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Choose your currency")
                } footer: {
                    Text("Every account is converted into this currency for the total. You can change it later without losing any history.")
                }

                Section {
                    Text("Your balances stay on this iPhone. Tally has no account to sign into and never uploads your data — the only thing it downloads is the European Central Bank's public exchange-rate file.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Welcome to Tally")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        settings.baseCurrency = selection
                        settings.hasCompletedSetup = true
                    }
                }
            }
        }
    }
}
