import SwiftUI

struct HostListView: View {
    @EnvironmentObject var store: HostStore
    @EnvironmentObject var keys: KeyStore
    @EnvironmentObject var sessions: SessionManager
    @State private var search = ""
    @State private var editing: SSHHost?
    @State private var passwordPromptHost: SSHHost?
    @State private var promptPassword = ""
    @State private var quickConnect = false
    @State private var errorText: String?

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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !sessions.sessions.isEmpty { sessionStrip }
                    if store.hosts.isEmpty {
                        emptyState
                    } else {
                        ForEach(grouped, id: \.0) { group, hosts in
                            VStack(alignment: .leading, spacing: 8) {
                                SectionTitle(group.isEmpty ? "호스트" : group, count: hosts.count)
                                VStack(spacing: 8) {
                                    ForEach(hosts) { host in hostCard(host) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .searchable(text: $search, prompt: "호스트 검색")
            .navigationTitle("Termi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = SSHHost() } label: { Label("새 호스트", systemImage: "server.rack") }
                        Button { quickConnect = true } label: { Label("빠른 연결", systemImage: "bolt.fill") }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.accent, in: Circle())
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(item: $editing) { host in HostEditView(host: host) }
            .sheet(isPresented: $quickConnect) { QuickConnectView() }
            .alert("비밀번호 입력", isPresented: Binding(
                get: { passwordPromptHost != nil },
                set: { if !$0 { passwordPromptHost = nil } }
            ), presenting: passwordPromptHost) { host in
                SecureField("비밀번호", text: $promptPassword)
                Button("연결") {
                    store.setPassword(promptPassword, for: host)
                    start(host, .password(promptPassword))
                    promptPassword = ""
                }
                Button("취소", role: .cancel) { promptPassword = "" }
            } message: { host in
                Text(host.subtitle)
            }
            .alert("연결할 수 없음", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: { Text(errorText ?? "") }
        }
    }

    // MARK: - Sessions

    private var sessionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("열린 세션", count: sessions.sessions.count)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sessions.sessions) { s in
                        SessionCard(session: s)
                            .onTapGesture { sessions.active = s }
                            .contextMenu {
                                Button(role: .destructive) { sessions.close(s) } label: {
                                    Label("세션 닫기", systemImage: "xmark")
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: - Host card

    private func hostCard(_ host: SSHHost) -> some View {
        Button { connect(host) } label: {
            HostRow(host: host, keyName: host.authKind == .key ? keys.key(host.keyID)?.name : nil)
        }
        .buttonStyle(CardButtonStyle())
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
            Button {
                UIPasteboard.general.string = "ssh \(host.username)@\(host.hostname)" + (host.port == 22 ? "" : " -p \(host.port)")
            } label: { Label("ssh 명령 복사", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive) { store.delete(host) } label: { Label("삭제", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 76, height: 76)
                .background(Color.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("첫 서버를 추가하세요").font(.title3.bold())
            Text("주소와 아이디만 넣으면 끝.\n비밀번호 또는 SSH 키로 로그인할 수 있어요.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textDim)
            HStack(spacing: 10) {
                Button { editing = SSHHost() } label: {
                    Label("새 호스트", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { quickConnect = true } label: {
                    Label("빠른 연결", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 10)
    }

    // MARK: - Connect

    private func connect(_ host: SSHHost) {
        switch host.authKind {
        case .key:
            guard let key = keys.key(host.keyID) else {
                errorText = "이 호스트에 지정된 SSH 키가 없습니다. 호스트를 편집해서 키를 선택하세요."
                return
            }
            start(host, .key(key))
        case .password:
            if let pw = store.password(for: host), !pw.isEmpty {
                start(host, .password(pw))
            } else {
                promptPassword = ""
                passwordPromptHost = host
            }
        }
    }

    private func start(_ host: SSHHost, _ cred: SSHCredential) {
        store.markConnected(host)
        _ = sessions.open(host: host, credential: cred)
    }
}

// MARK: - Components

struct SectionTitle: View {
    let title: String
    var count: Int?
    init(_ title: String, count: Int? = nil) { self.title = title; self.count = count }

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
        .foregroundStyle(Color.textDim)
        .padding(.leading, 4)
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.panelRaised : Color.panel,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hairline))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HostAvatar: View {
    let host: SSHHost
    var size: CGFloat = 40

    var body: some View {
        let c = Color.tag(for: host.hostname + host.username)
        Text(host.initial)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(c)
            .frame(width: size, height: size)
            .background(c.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct HostRow: View {
    let host: SSHHost
    var keyName: String?

    var body: some View {
        HStack(spacing: 12) {
            HostAvatar(host: host)
            VStack(alignment: .leading, spacing: 3) {
                Text(host.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: host.authKind == .key ? "key.horizontal.fill" : "lock.fill")
                        .font(.system(size: 9))
                    Text(host.subtitle)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.textDim)
            }
            Spacer(minLength: 8)
            if let d = host.lastConnected {
                Text(d, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textDim.opacity(0.7))
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textDim.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct SessionCard: View {
    @ObservedObject var session: SSHSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HostAvatar(host: session.host, size: 30)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(label).font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.textDim)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.host.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(session.host.subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textDim)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 180, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.35)))
        .contentShape(Rectangle())
    }

    private var color: Color {
        switch session.state {
        case .connected: return .accentGreen
        case .connecting, .idle: return .orange
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
