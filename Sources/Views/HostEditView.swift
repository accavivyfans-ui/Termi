import SwiftUI

struct HostEditView: View {
    @EnvironmentObject var store: HostStore
    @EnvironmentObject var keys: KeyStore
    @Environment(\.dismiss) private var dismiss
    @State var host: SSHHost
    @State private var password = ""
    @State private var portText = "22"
    @State private var showPassword = false
    @State private var auth: AuthKind = .password
    @State private var newKeySheet = false

    private var isNew: Bool { !store.hosts.contains { $0.id == host.id } }
    private var valid: Bool {
        !host.hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && !host.username.trimmingCharacters(in: .whitespaces).isEmpty
            && Int(portText) != nil
            && (auth == .password || keys.key(host.keyID)?.canLogin == true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        HostAvatar(host: host, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("이름 (예: 집 서버)", text: $host.label)
                                .font(.headline)
                            TextField("그룹 (선택)", text: $host.group)
                                .font(.subheadline)
                                .foregroundStyle(Color.textDim)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.panel)

                Section("주소") {
                    LabeledField("호스트") {
                        TextField("192.168.0.10", text: $host.hostname)
                            .keyboardType(.URL)
                    }
                    LabeledField("포트") {
                        TextField("22", text: $portText).keyboardType(.numberPad)
                    }
                    LabeledField("아이디") {
                        TextField("root", text: $host.username)
                    }
                }
                .listRowBackground(Color.panel)

                Section {
                    Picker("인증", selection: $auth) {
                        ForEach(AuthKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if auth == .password {
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("비밀번호", text: $password)
                                } else {
                                    SecureField("비밀번호", text: $password)
                                }
                            }
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.textDim)
                        }
                        .listRowBackground(Color.panel)
                    } else {
                        if keys.loginKeys.isEmpty {
                            Button { newKeySheet = true } label: {
                                Label("키 만들기 / 가져오기", systemImage: "key.horizontal")
                            }
                            .listRowBackground(Color.panel)
                        } else {
                            ForEach(keys.loginKeys) { k in
                                Button { host.keyID = k.id } label: {
                                    HStack {
                                        KeyBadge(key: k)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(k.name).foregroundStyle(.white)
                                            Text(k.fingerprint).font(.caption2.monospaced())
                                                .foregroundStyle(Color.textDim).lineLimit(1)
                                        }
                                        Spacer()
                                        if host.keyID == k.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accent)
                                        }
                                    }
                                }
                                .listRowBackground(Color.panel)
                            }
                            Button { newKeySheet = true } label: {
                                Label("다른 키 추가", systemImage: "plus")
                            }
                            .listRowBackground(Color.panel)
                        }
                    }
                } header: {
                    Text("로그인").padding(.bottom, 6)
                } footer: {
                    Text(auth == .password
                         ? "비워두면 접속할 때마다 물어봅니다. 비밀번호는 iPhone 키체인에 암호화되어 보관됩니다."
                         : "서버의 ~/.ssh/authorized_keys 에 이 키의 공개키가 등록되어 있어야 합니다. 비밀번호로 한 번 접속한 뒤 터미널 메뉴 → '내 공개키를 이 서버에 등록'을 누르면 자동으로 등록돼요.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle(isNew ? "새 호스트" : "호스트 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        host.hostname = host.hostname.trimmingCharacters(in: .whitespaces)
                        host.username = host.username.trimmingCharacters(in: .whitespaces)
                        host.port = Int(portText) ?? 22
                        host.auth = auth
                        store.upsert(host, password: auth == .password ? password : nil)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!valid)
                }
            }
            .sheet(isPresented: $newKeySheet) {
                AddKeyView { created in host.keyID = created.id }
            }
            .onAppear {
                portText = String(host.port)
                password = store.password(for: host) ?? ""
                auth = host.authKind
                if host.keyID == nil { host.keyID = keys.loginKeys.first?.id }
            }
        }
    }
}

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        HStack {
            Text(label).foregroundStyle(Color.textDim).frame(width: 64, alignment: .leading)
            content.font(.body.monospaced())
        }
    }
}

struct QuickConnectView: View {
    @EnvironmentObject var store: HostStore
    @EnvironmentObject var keys: KeyStore
    @EnvironmentObject var sessions: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var password = ""
    @State private var auth: AuthKind = .password
    @State private var keyID: UUID?
    @State private var save = false

    /// "user@host:port" 또는 "ssh user@host -p port" 파싱
    private var parsed: SSHHost? {
        var t = target.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("ssh ") { t = String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
        var port = 22
        if let r = t.range(of: " -p ") {
            port = Int(t[r.upperBound...].trimmingCharacters(in: .whitespaces)) ?? 22
            t = String(t[..<r.lowerBound])
        }
        guard let at = t.firstIndex(of: "@") else { return nil }
        let user = String(t[..<at])
        var rest = String(t[t.index(after: at)...])
        if let colon = rest.lastIndex(of: ":"), let p = Int(rest[rest.index(after: colon)...]) {
            port = p
            rest = String(rest[..<colon])
        }
        guard !user.isEmpty, !rest.isEmpty else { return nil }
        return SSHHost(hostname: rest, port: port, username: user)
    }

    private var ready: Bool {
        parsed != nil && (auth == .password ? !password.isEmpty : keys.key(keyID)?.canLogin == true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("user@host:22", text: $target)
                        .keyboardType(.URL)
                        .font(.body.monospaced())
                } footer: {
                    Text("예: root@192.168.0.10 · ubuntu@example.com:2222 · ssh pi@raspberrypi -p 22")
                }
                .listRowBackground(Color.panel)
                Section {
                    Picker("인증", selection: $auth) {
                        ForEach(AuthKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    if auth == .password {
                        SecureField("비밀번호", text: $password).listRowBackground(Color.panel)
                    } else if keys.loginKeys.isEmpty {
                        Text("키체인 탭에서 먼저 키를 만들거나 가져오세요.")
                            .foregroundStyle(Color.textDim)
                            .listRowBackground(Color.panel)
                    } else {
                        Picker("키", selection: $keyID) {
                            ForEach(keys.loginKeys) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .listRowBackground(Color.panel)
                    }
                    Toggle("호스트로 저장", isOn: $save).listRowBackground(Color.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("빠른 연결")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { keyID = keys.loginKeys.first?.id }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("연결") {
                        guard var host = parsed else { return }
                        host.auth = auth
                        host.keyID = auth == .key ? keyID : nil
                        if save { store.upsert(host, password: auth == .password ? password : nil) }
                        dismiss()
                        if auth == .key, let k = keys.key(keyID) {
                            _ = sessions.open(host: host, credential: .key(k))
                        } else {
                            _ = sessions.open(host: host, credential: .password(password))
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!ready)
                }
            }
        }
    }
}
