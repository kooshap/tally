import SwiftData
import SwiftUI

@main
struct TallyApp: App {
    /// Local store only — no CloudKit container is configured, so nothing syncs.
    /// It lives in Application Support, which the standard iPhone backup covers.
    /// If it can't be opened, the app shows `StoreRecoveryView` rather than
    /// stopping.
    @State private var store = StoreLoader(open: UITestSupport.makeContainer)

    @State private var settings = UITestSupport.makeSettings()
    @State private var rates = RatesCoordinator()
    @State private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            if UITestSupport.isHostingUnitTests {
                Color.clear
            } else {
                switch store.state {
                case .ready(let container):
                    AppRootView()
                        .environment(settings)
                        .environment(rates)
                        .environment(lock)
                        .modelContainer(container)
                case .failed(let failure):
                    StoreRecoveryView(failure: failure) {
                        store.tryAgain()
                    }
                }
            }
        }
    }
}
