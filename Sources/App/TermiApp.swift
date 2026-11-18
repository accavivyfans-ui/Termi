import SwiftUI

@main
struct TermiApp: App {
    @StateObject private var store = HostStore()
    @StateObject private var keys = KeyStore()
    @StateObject private var sessions = SessionManager()

    init() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(hex: 0x0E1016)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(hex: 0x12141B)
        tab.shadowColor = UIColor.white.withAlphaComponent(0.06)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(keys)
                .environmentObject(sessions)
                .preferredColorScheme(.dark)
                .tint(.accent)
                .onAppear {
                    let mgr = sessions
                    BackgroundKeeper.shared.hasSessions = { [weak mgr] in
                        mgr?.sessions.contains { $0.state == .connected || $0.state == .connecting } ?? false
                    }
                    BackgroundKeeper.shared.start()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var sessions: SessionManager

    var body: some View {
        TabView {
            HostListView()
                .tabItem { Label("호스트", systemImage: "server.rack") }
            KeychainView()
                .tabItem { Label("키체인", systemImage: "key.horizontal") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: Binding(
            get: { sessions.active != nil },
            set: { if !$0 { sessions.active = nil } }
        )) {
            if let s = sessions.active {
                TerminalScreen(session: s).id(s.id)
            }
        }
    }
}
