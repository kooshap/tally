import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Net worth", systemImage: "chart.xyaxis.line") {
                DashboardView()
            }
            Tab("Accounts", systemImage: "list.bullet") {
                AccountsListView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
