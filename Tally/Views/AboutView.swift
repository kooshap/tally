import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section("Privacy") {
                Text("Your accounts, balances and notes are stored only on this iPhone. Tally has no servers, no account to sign into, and no analytics or crash-reporting of any kind. Nothing you type is ever uploaded.")
                Text("The one thing Tally downloads is the European Central Bank's public exchange-rate file, so it can convert currencies. That request carries no identifier and says nothing about you or your accounts — it is the same file anyone can open in a browser.")
                Text("Your data is included in your normal encrypted iPhone backup, which is how it survives a lost or replaced phone. There is no separate Tally cloud.")
            }

            Section("Working offline") {
                Text("Tally works with no connection at all. It uses the last rates it downloaded and tells you the date they came from. If a day has no rate, that day is left off the chart rather than estimated.")
            }

            Section {
                LabeledContent("Rate source") {
                    Text("European Central Bank")
                }
                Link("ecb.europa.eu", destination: URL(string: "https://www.ecb.europa.eu/stats/eurofxref/")!)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
