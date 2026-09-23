import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // The store lives on-device only. No CloudKit container, no sync.
        .modelContainer(for: [Account.self, ValueSnapshot.self])
    }
}
