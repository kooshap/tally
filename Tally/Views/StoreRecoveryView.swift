import SwiftUI

/// Shown instead of the app when the store won't open, for example after an
/// update whose migration failed.
///
/// It says first that the data is still there, because the obvious fix for a
/// broken app, deleting and reinstalling it, is the one thing that would
/// really lose it. Nothing here writes to the store: "Try again" only opens it
/// again.
struct StoreRecoveryView: View {
    let failure: StoreFailure
    let tryAgain: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Tally can't open your data")
                    .font(.headline)

                Text(
                    "Your accounts and balances have not been deleted. They are still on this iPhone, and nothing on this screen will change or remove them."
                )

                Text(
                    "Please don't delete the app to fix this — that would delete your data with it. Updating Tally from the App Store, or restarting your iPhone, may help."
                )
                .foregroundStyle(.secondary)

                Button("Try again", action: tryAgain)
                    .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Technical details")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: failure.details)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Tally doesn't send error reports. These details stay on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                .padding(.top, 16)
            }
            .multilineTextAlignment(.center)
            .padding()
        }
    }
}
