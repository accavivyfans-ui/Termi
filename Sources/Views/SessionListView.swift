import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var sessions: SessionManager

    var body: some View {
        NavigationStack {
            Group {
                if sessions.sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "terminal").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("열린 세션이 없습니다").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
                } else {
                    List {
                        ForEach(sessions.sessions) { s in
                            SessionRow(session: s)
                                .contentShape(Rectangle())
                                .onTapGesture { sessions.active = s }
                                .listRowBackground(Color.panel)
                                .swipeActions {
                                    Button(role: .destructive) { sessions.close(s) } label: {
                                        Label("닫기", systemImage: "xmark")
                                    }
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.appBackground)
                }
            }
            .navigationTitle("세션")
        }
    }
}

struct SessionRow: View {
    @ObservedObject var session: SSHSession

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading) {
                Text(session.title).font(.headline).lineLimit(1)
                Text(session.host.subtitle).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch session.state {
        case .connected: return .accentGreen
        case .connecting, .idle: return .yellow
        case .closed: return .red
        }
    }
    private var label: String {
        switch session.state {
        case .connected: return "연결됨"
        case .connecting, .idle: return "연결 중"
        case .closed: return "종료됨"
        }
    }
}
