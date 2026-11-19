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
                                        HStack(spacing: 6) {
                                            Text(k.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                            if !k.canLogin { PublicOnlyTag() }
                                        }
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
            Text("여기서 키를 새로 만들거나, PC의 키 파일(id_ed25519 / id_ed25519.pub 등)을 가져오세요. 로그인에는 개인키가 필요하고, 공개키(.pub)만 가져오면 복사·서버 등록용으로 쓸 수 있어요.")
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

struct PublicOnlyTag: View {
    var body: some View {
        Text("공개키만")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(.orange)
    }
}

extension UTType {
    /// .pub — iOS가 Publisher 문서 등으로 오인해 회색 처리하는 경우가 있어 확장자로 직접 등록
    static let sshPublicKey: UTType = UTType(filenameExtension: "pub", conformingTo: .data)
        ?? UTType(filenameExtension: "pub") ?? .data
    static let sshKeyFiles: [UTType] = {
        var types: [UTType] = [.sshPublicKey, .plainText, .text, .data, .content, .item]
        for ext in ["pem", "key", "ppk"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }()
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
    @State private var pubText = ""
    @State private var fileName: String?
    @State private var passphrase = ""
    @State private var importing = false
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
                        Button { importing = true } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text(fileName ?? "키 파일 선택 (id_ed25519, .pub …)")
                                    .lineLimit(1)
                                Spacer()
                                if fileName != nil { Image(systemName: "checkmark").foregroundStyle(Color.accentGreen) }
                            }
                        }
                        if !isPublicOnlyImport {
                            SecureField("암호 (passphrase, 없으면 비움)", text: $passphrase)
                        }
                    } footer: {
                        Text(isPublicOnlyImport
                             ? "공개키(.pub)만 골랐어요. 복사·GitHub·서버 등록용으로 저장되고, 로그인하려면 나중에 짝이 되는 개인키를 가져오면 같은 항목에 합쳐져요."
                             : "개인키(id_ed25519)와 공개키(.pub)를 함께 골라도 되고, .pub만 골라도 돼요. 파일 앱 → iCloud / 이 iPhone / Termi 폴더에서 선택할 수 있어요.")
                    }
                    .listRowBackground(Color.panel)
                case .paste:
                    Section {
                        TextEditor(text: $pem)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 160)
                            .overlay(alignment: .topLeading) {
                                if pem.isEmpty {
                                    Text("-----BEGIN OPENSSH PRIVATE KEY-----\n…\n\n또는 공개키 한 줄: ssh-ed25519 AAAA…")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.textDim.opacity(0.6))
                                        .padding(.top, 8).padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                        Button("클립보드에서 붙여넣기") { pem = UIPasteboard.general.string ?? "" }
                        if !isPublicOnlyImport {
                            SecureField("암호 (passphrase, 없으면 비움)", text: $passphrase)
                        }
                    }
                    .listRowBackground(Color.panel)
                }

                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
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
                        .disabled(mode != .generate && pem.isEmpty && pubText.isEmpty)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: UTType.sshKeyFiles, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): load(urls)
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    private var isPublicOnlyImport: Bool {
        switch mode {
        case .generate: return false
        case .file: return pem.isEmpty && !pubText.isEmpty
        case .paste: return SSHWire.looksLikePublicKey(pem)
        }
    }

    private func load(_ urls: [URL]) {
        var priv = "", pub = "", names: [String] = [], baseName: String?
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? Data(contentsOf: url)).flatMap({ String(data: $0, encoding: .ascii) }) else {
                error = "파일을 읽을 수 없습니다: \(url.lastPathComponent)"
                return
            }
            names.append(url.lastPathComponent)
            if url.pathExtension.lowercased() == "pub" || SSHWire.looksLikePublicKey(text) {
                pub = text
                if baseName == nil { baseName = url.deletingPathExtension().lastPathComponent }
            } else {
                priv = text
                baseName = url.deletingPathExtension().lastPathComponent
            }
        }
        pem = priv
        pubText = pub
        fileName = names.joined(separator: " + ")
        if name == "iPhone" || name.isEmpty, let baseName { name = baseName }
        error = nil
        if priv.isEmpty, !pub.isEmpty, (try? SSHWire.parsePublicKey(pub)) == nil {
            error = KeyError.notPublicKey.localizedDescription
        }
    }

    private func commit() {
        do {
            let item: SSHKeyItem
            if mode == .generate {
                item = keys.generateEd25519(name: name.isEmpty ? "iPhone" : name)
            } else if isPublicOnlyImport {
                item = try keys.importPublicKey(mode == .file ? pubText : pem, name: name)
            } else {
                item = try keys.importPrivateKey(pem, name: name, passphrase: passphrase,
                                                 publicKey: mode == .file ? pubText : nil)
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

                if !key.canLogin {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("공개키(.pub)만 있는 항목이라 로그인에는 쓸 수 없어요. 복사·GitHub·서버 등록용입니다. 짝이 되는 개인키를 키체인에서 가져오면 이 항목에 합쳐져요.")
                            .font(.footnote).foregroundStyle(Color.textDim)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
