import SwiftUI

struct HostListView: View {
    @EnvironmentObject var store: HostStore
    @EnvironmentObject var sessions: SessionManager
    @State private var search = ""
    @State private var editing: SSHHost?
    @State private var passwordPromptHost: SSHHost?
    @State private var promptPassword = ""
    @State private var savePrompted = true
    @State private var quickConnect = false

    private var filtered: [SSHHost] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? store.hosts : store.hosts.filter {
            $0.displayName.lowercased().contains(q) || $0.hostname.lowercased().contains(q)
                || $0.username.lowercased().contains(q) || $0.group.lowercased().contains(q)
        }
        return list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var grouped: [(String, [SSHHost])] {
        Dictionary(grouping: filtered) { $0.group.trimmingCharacters(in: .whitespaces) }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.hosts.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(grouped, id: \.0) { group, hosts in
                            Section(group.isEmpty ? "호스트" : group) {
                                ForEach(hosts) { host in
                                    HostRow(host: host)
                                        .contentShape(Rectangle())
                                        .onTapGesture { connect(host) }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { store.delete(host) } label: {
                                                Label("삭제", systemImage: "trash")
                                            }
                                            Button { editing = host } label: {
                                                Label("편집", systemImage: "pencil")
                                            }.tint(.blue)
                                        }
                                        .contextMenu {
                                            Button { connect(host) } label: { Label("연결", systemImage: "play.fill") }
                                            Button { editing = host } label: { Label("편집", systemImage: "pencil") }
                                            Button {
                                                var copy = host
                                                copy.id = UUID()
                                                copy.label = host.displayName + " 복사본"
                                                copy.lastConnected = nil
                                                store.upsert(copy, password: store.password(for: host))
                                            } label: { Label("복제", systemImage: "plus.square.on.square") }
                                            Button(role: .destructive) { store.delete(host) } label: {
                                                Label("삭제", systemImage: "trash")
                                            }
                                        }
                                        .listRowBackground(Color.panel)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.appBackground)
                    .searchable(text: $search, prompt: "호스트 검색")
                }
            }
            .navigationTitle("호스트")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { quickConnect = true } label: { Image(systemName: "bolt.fill") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = SSHHost() } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { host in
                HostEditView(host: host)
            }
            .sheet(isPresented: $quickConnect) {
                QuickConnectView()
            }
            .alert("비밀번호 입력", isPresented: Binding(
                get: { passwordPromptHost != nil },
                set: { if !$0 { passwordPromptHost = nil } }
            ), presenting: passwordPromptHost) { host in
                SecureField("비밀번호", text: $promptPassword)
                Button("연결") {
                    store.setPassword(promptPassword, for: host)
                    start(host, password: promptPassword)
                    promptPassword = ""
                }
                Button("취소", role: .cancel) { promptPassword = "" }
            } message: { host in
                Text(host.subtitle)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentGreen)
            Text("저장된 호스트가 없습니다").font(.title3.bold())
            Text("서버 주소, 아이디, 비밀번호를 저장하고\n탭 한 번으로 접속하세요.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                editing = SSHHost()
            } label: {
                Label("새 호스트", systemImage: "plus").padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private func connect(_ host: SSHHost) {
        if let pw = store.password(for: host), !pw.isEmpty {
            start(host, password: pw)
        } else {
            promptPassword = ""
            passwordPromptHost = host
        }
    }

    private func start(_ host: SSHHost, password: String) {
        store.markConnected(host)
        _ = sessions.open(host: host, password: password)
    }
}

struct HostRow: View {
    let host: SSHHost

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentGreen.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: "terminal.fill")
                    .foregroundStyle(Color.accentGreen)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(host.displayName).font(.headline)
                Text(host.subtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let d = host.lastConnected {
                Text(d, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
