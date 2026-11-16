import SwiftUI

@main
struct TermiApp: App {
    @StateObject private var store = HostStore()
    @StateObject private var sessions = SessionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(sessions)
                .preferredColorScheme(.dark)
                .tint(.accentGreen)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var sessions: SessionManager

    var body: some View {
        TabView {
            HostListView()
                .tabItem { Label("호스트", systemImage: "server.rack") }
            SessionListView()
                .tabItem { Label("세션", systemImage: "terminal") }
                .badge(sessions.sessions.count)
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .fullScreenCover(item: $sessions.active) { session in
            TerminalScreen(session: session)
        }
    }
}
