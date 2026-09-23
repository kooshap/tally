import SwiftUI
import SwiftData

struct AppRootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RatesCoordinator.self) private var rates
    @Environment(AppLock.self) private var lock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !settings.hasCompletedSetup {
                FirstLaunchView()
            } else if lock.isLocked(enabled: settings.faceIDEnabled) {
                LockGateView()
            } else {
                MainTabView()
            }
        }
        // Hide balances in the app switcher whenever the lock is on.
        .overlay {
            if settings.faceIDEnabled && scenePhase != .active {
                PrivacyShade()
            }
        }
        .task {
            rates.loadCached(from: modelContext)
            await rates.refreshIfNeeded(context: modelContext, settings: settings)
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-lock on leaving, not on a passing interruption like a
            // notification banner, which only makes the scene inactive.
            if phase == .background && settings.faceIDEnabled {
                lock.lock()
            }
        }
    }
}

/// Opaque rather than a blur: a blurred six-figure number is still a six-figure
/// number.
private struct PrivacyShade: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
