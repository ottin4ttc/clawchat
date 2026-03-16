import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("主页", systemImage: "message.fill", value: 0) {
                NavigationStack {
                    HomeView()
                }
            }

            Tab("看板", systemImage: "square.grid.2x2.fill", value: 1) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab("Agent", systemImage: "person.fill", value: 2) {
                NavigationStack {
                    AgentProfileView()
                }
            }
        }
        .tint(appState.currentVisualTheme.accent)
        .preferredColorScheme(isDarkMode ? .dark : nil)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
