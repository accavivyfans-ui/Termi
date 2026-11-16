import SwiftUI

struct HostEditView: View {
    @EnvironmentObject var store: HostStore
    @Environment(\.dismiss) private var dismiss
    @State var host: SSHHost
    @State private var password = ""
    @State private var portText = "22"
    @State private var showPassword = false

    private var isNew: Bool { !store.hosts.contains { $0.id == host.id } }
    private var valid: Bool {
        !host.hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && !host.username.trimmingCharacters(in: .whitespaces).isEmpty
            && Int(portText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("일반") {
                    TextField("이름 (선택)", text: $host.label)
                    TextField("그룹 (선택)", text: $host.group)
                }
                Section("주소") {
                    TextField("호스트 / IP", text: $host.hostname)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("포트", text: $portText)
                        .keyboardType(.numberPad)
                }
                Section {
                    TextField("아이디", text: $host.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Group {
                            if showPassword {
                                TextField("비밀번호", text: $password)
                            } else {
                                SecureField("비밀번호", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("로그인")
                } footer: {
                    Text("비밀번호를 비워두면 접속할 때마다 물어봅니다. 저장된 비밀번호는 iPhone 키체인에 암호화되어 보관됩니다.")
                }
            }
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
                        store.upsert(host, password: password)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
            .onAppear {
                portText = String(host.port)
                password = store.password(for: host) ?? ""
            }
        }
    }
}

struct QuickConnectView: View {
    @EnvironmentObject var store: HostStore
    @EnvironmentObject var sessions: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var password = ""
    @State private var save = false

    /// "user@host:port" 파싱
    private var parsed: SSHHost? {
        let t = target.trimmingCharacters(in: .whitespaces)
        guard let at = t.firstIndex(of: "@") else { return nil }
        let user = String(t[..<at])
        var rest = String(t[t.index(after: at)...])
        var port = 22
        if let colon = rest.lastIndex(of: ":"), let p = Int(rest[rest.index(after: colon)...]) {
            port = p
            rest = String(rest[..<colon])
        }
        guard !user.isEmpty, !rest.isEmpty else { return nil }
        return SSHHost(hostname: rest, port: port, username: user)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("user@host:22", text: $target)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    SecureField("비밀번호", text: $password)
                    Toggle("호스트로 저장", isOn: $save)
                } footer: {
                    Text("예: root@192.168.0.10 또는 ubuntu@example.com:2222")
                }
            }
            .navigationTitle("빠른 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("연결") {
                        guard let host = parsed else { return }
                        if save { store.upsert(host, password: password) }
                        dismiss()
                        _ = sessions.open(host: host, password: password)
                    }
                    .disabled(parsed == nil || password.isEmpty)
                }
            }
        }
    }
}
