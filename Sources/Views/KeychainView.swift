import SwiftUI
import UniformTypeIdentifiers

struct KeychainView: View {
    @EnvironmentObject var keys: KeyStore
    @State private var adding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if keys.keys.isEmpty {
                        empty
                    } else {
                        SectionTitle("SSH 키", count: keys.keys.count)
                        ForEach(keys.keys) { k in
                            NavigationLink(value: k) {
                                HStack(spacing: 12) {
                                    KeyBadge(key: k)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(k.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                        Text(k.fingerprint)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Color.textDim)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.textDim.opacity(0.5))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("키체인")
            .navigationDestination(for: SSHKeyItem.self) { KeyDetailView(key: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.accent, in: Circle())
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $adding) { AddKeyView() }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 76, height: 76)
                .background(Color.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("SSH 키로 비밀번호 없이 로그인").font(.title3.bold())
            Text("여기서 키를 새로 만들거나, PC의 개인키 파일(id_ed25519 등)을 가져오세요. 공개키(.pub)는 서버나 GitHub에 등록하면 됩니다.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textDim)
            Button { adding = true } label: {
                Label("키 추가", systemImage: "plus").frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 10)
    }
}

struct KeyBadge: View {
    let key: SSHKeyItem
    var body: some View {
        Image(systemName: "key.horizontal.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.accentGreen)
            .frame(width: 40, height: 40)
            .background(Color.accentGreen.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text(key.typeLabel == "ED25519" ? "ED" : key.typeLabel)
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(Color.panelRaised, in: Capsule())
                    .foregroundStyle(Color.textDim)
                    .offset(x: 4, y: 4)
            }
    }
}

// MARK: - Add

struct AddKeyView: View {
    @EnvironmentObject var keys: KeyStore
    @Environment(\.dismiss) private var dismiss
    var onCreated: ((SSHKeyItem) -> Void)?

    enum Mode: String, CaseIterable, Identifiable {
        case generate, file, paste
        var id: String { rawValue }
        var title: String {
            switch self {
            case .generate: return "새로 만들기"
            case .file: return "파일"
            case .paste: return "붙여넣기"
            }
        }
    }

    @State private var mode: Mode = .generate
    @State private var name = "iPhone"
    @State private var pem = ""
    @State private var fileName: String?
    @State private var passphrase = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("방식", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    .listRowBackground(Color.panel)
                }

                Section("이름") {
                    TextField("키 이름", text: $name)
                }
                .listRowBackground(Color.panel)

                switch mode {
                case .generate:
                    Section {
                        Label("ED25519 · 가장 빠르고 안전한 최신 방식", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.accentGreen)
                    } footer: {
                        Text("개인키는 이 iPhone 키체인 안에만 저장됩니다. 만든 뒤 공개키를 서버 / GitHub에 등록하세요.")
                    }
                    .listRowBackground(Color.panel)
                case .file:
                    Section {
                        Button { pickFile() } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text(fileName ?? "개인키 파일 선택 (id_ed25519, id_rsa …)")
                                    .lineLimit(1)
                                Spacer()
                                if fileName != nil { Image(systemName: "checkmark").foregroundStyle(Color.accentGreen) }
                            }
                        }
                        SecureField("암호 (passphrase, 없으면 비움)", text: $passphrase)
                    } footer: {
                        Text("`.pub`가 아닌 개인키 파일을 고르세요. 파일 앱 → iCloud / 이 iPhone / Termi 폴더에서 선택할 수 있어요.")
                    }
                    .listRowBackground(Color.panel)
                case .paste:
                    Section {
                        TextEditor(text: $pem)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 160)
                            .overlay(alignment: .topLeading) {
                                if pem.isEmpty {
                                    Text("-----BEGIN OPENSSH PRIVATE KEY-----\n…")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.textDim.opacity(0.6))
                                        .padding(.top, 8).padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                        Button("클립보드에서 붙여넣기") { pem = UIPasteboard.general.string ?? "" }
                        SecureField("암호 (passphrase, 없으면 비움)", text: $passphrase)
                    }
                    .listRowBackground(Color.panel)
                }

            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("SSH 키 추가")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) { _, _ in error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .generate ? "만들기" : "가져오기") { commit() }
                        .fontWeight(.semibold)
                        .disabled(mode != .generate && pem.isEmpty)
                }
            }
        }
    }

    private func pickFile() {
        DocumentPicker.present { result, url in
            switch result {
            case .success(let data):
                let text = String(decoding: data, as: UTF8.self)
                    .replacingOccurrences(of: "\r\n", with: "\n")
                pem = text
                fileName = url?.lastPathComponent
                if let url, name == "iPhone" || name.isEmpty {
                    name = url.deletingPathExtension().lastPathComponent
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if url?.pathExtension == "pub" || trimmed.hasPrefix("ssh-") {
                    error = "이건 공개키(.pub)예요. 로그인하려면 짝이 되는 개인키 파일(확장자 없는 id_ed25519 등)이 필요해요."
                } else if trimmed.isEmpty {
                    error = "빈 파일이에요."
                } else {
                    error = nil
                }
            case .failure(let e):
                error = "파일을 읽을 수 없습니다: \(e.localizedDescription)"
            }
        }
    }

    private func commit() {
        do {
            let item: SSHKeyItem
            if mode == .generate {
                item = keys.generateEd25519(name: name.isEmpty ? "iPhone" : name)
            } else {
                item = try keys.importPrivateKey(pem, name: name, passphrase: passphrase)
            }
            onCreated?(item)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Detail

struct KeyDetailView: View {
    @EnvironmentObject var keys: KeyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let key: SSHKeyItem
    @State private var name = ""
    @State private var copied = false
    @State private var confirmDelete = false

    private var pubFile: URL {
        let safe = key.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "termi" : safe).pub")
        try? (key.publicKey + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    KeyBadge(key: key)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("이름", text: $name, onCommit: { keys.rename(key, to: name) })
                            .font(.title3.bold())
                        Text("\(key.typeLabel) · \(key.created.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(Color.textDim)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("공개키")
                    Text(key.publicKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.hairline))
                    Text(key.fingerprint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textDim)
                        .padding(.leading, 4)
                }

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = key.publicKey
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Label(copied ? "복사됨" : "복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    ShareLink(item: pubFile) {
                        Label(".pub 내보내기", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)

                Button {
                    UIPasteboard.general.string = key.publicKey
                    if let u = URL(string: "https://github.com/settings/ssh/new") { openURL(u) }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.forward.app")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GitHub에 등록").font(.system(size: 15, weight: .semibold))
                            Text("공개키를 복사하고 GitHub 'New SSH key' 페이지를 엽니다 — Key 칸에 붙여넣기")
                                .font(.caption).foregroundStyle(Color.textDim)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(14)
                }
                .buttonStyle(CardButtonStyle())
                .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("서버에 등록하는 법")
                    VStack(alignment: .leading, spacing: 10) {
                        step(1, "비밀번호로 서버에 한 번 접속")
                        step(2, "터미널 오른쪽 위 ⋯ → '내 공개키를 이 서버에 등록'")
                        step(3, "호스트 편집 → 인증을 'SSH 키'로 바꾸고 이 키 선택")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("GitHub에 등록했다면 서버에서 `curl https://github.com/아이디.keys >> ~/.ssh/authorized_keys` 로도 가져올 수 있어요.")
                        .font(.caption).foregroundStyle(Color.textDim)
                        .padding(.horizontal, 4)
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("키 삭제", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("키")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = key.name }
        .onDisappear { if name != key.name && !name.isEmpty { keys.rename(key, to: name) } }
        .confirmationDialog("이 키를 삭제할까요? 이 키를 쓰는 호스트는 접속할 수 없게 됩니다.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                keys.delete(key)
                dismiss()
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Color.accent.opacity(0.2), in: Circle())
                .foregroundStyle(Color.accent)
            Text(text).font(.subheadline)
        }
    }
}
