import SwiftUI

struct LockGateView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Tally is locked")
                .font(.headline)

            if let failure = lock.lastFailure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Unlock") {
                Task { await authenticate() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .task { await authenticate() }
    }

    private func authenticate() async {
        await lock.authenticate(reason: String(localized: "Unlock Tally to see your balances."))
    }
}
