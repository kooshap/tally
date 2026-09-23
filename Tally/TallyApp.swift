import SwiftData
import SwiftUI

@main
struct TallyApp: App {
    /// Local store only — no CloudKit container is configured, so nothing syncs.
    /// It lives in Application Support, which the standard iPhone backup covers.
    private let container: ModelContainer = {
        do {
            return try UITestSupport.makeContainer()
        } catch {
            fatalError("Could not open the local store: \(error)")
        }
    }()

    @State private var settings = UITestSupport.makeSettings()
    @State private var rates = RatesCoordinator()
    @State private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            if UITestSupport.isHostingUnitTests {
                Color.clear
            } else {
                AppRootView()
                    .environment(settings)
                    .environment(rates)
                    .environment(lock)
            }
        }
        .modelContainer(container)
    }
}
