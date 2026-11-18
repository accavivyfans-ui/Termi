import SwiftUI
import SwiftTerm

struct TerminalScreen: View {
    @ObservedObject var session: SSHSession
    @EnvironmentObject var sessions: SessionManager
    @EnvironmentObject var keys: KeyStore
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("theme") private var themeRaw: String = TerminalTheme.midnight.rawValue
    @State private var keyboardVisible = false
    @State private var fullscreen = false
    @State private var installKeyPicker = false

    private var theme: TerminalTheme { TerminalTheme(rawValue: themeRaw) ?? .midnight }
    private var bg: SwiftUI.Color { SwiftUI.Color(hex: theme.colors.bg) }

    var body: some View {
        VStack(spacing: 0) {
            if !fullscreen { header.transition(.move(edge: .top).combined(with: .opacity)) }
            ZStack(alignment: .bottomTrailing) {
                TerminalContainer(session: session, fontSize: fontSize, theme: theme)
                    .ignoresSafeArea(.container, edges: .bottom)
                if !keyboardVisible { floatingControls }
            }
        }
        .background(bg.ignoresSafeArea())
        .statusBarHidden(fullscreen)
        .animation(.easeOut(duration: 0.2), value: fullscreen)
        .animation(.easeOut(duration: 0.2), value: keyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .confirmationDialog("이 서버에 등록할 공개키", isPresented: $installKeyPicker, titleVisibility: .visible) {
            ForEach(keys.keys) { k in
                Button("\(k.name) · \(k.typeLabel)") { install(k) }
            }
        } message: {
            Text("~/.ssh/authorized_keys 에 추가합니다. 다음부터 비밀번호 없이 접속돼요.")
        }
        .alert(item: $session.hostKeyPrompt) { prompt in
            Alert(
                title: Text(prompt.changed ? "⚠️ 서버 키가 변경됨" : "새 서버"),
                message: Text((prompt.changed
                    ? "이전에 저장된 키와 다릅니다. 서버가 재설치된 게 아니라면 중간자 공격일 수 있습니다.\n\n"
                    : "처음 접속하는 서버입니다. 지문을 확인하세요.\n\n")
                    + "\(prompt.hostID)\n\(prompt.keyType)\n\(prompt.fingerprint)"),
                primaryButton: .default(Text(prompt.changed ? "그래도 신뢰" : "신뢰하고 연결")) {
                    session.answerHostKey(true)
                },
                secondaryButton: .cancel(Text("취소")) { session.answerHostKey(false) }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                sessions.active = nil
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(SwiftUI.Color.white.opacity(0.06), in: Circle())
            }
            .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sessions.sessions) { s in
                        SessionTab(session: s, selected: s.id == session.id) {
                            sessions.active = s
                        }
                    }
                }
            }

            Menu {
                Button {
                    if let s = UIPasteboard.general.string { session.sendText(s) }
                } label: { Label("붙여넣기", systemImage: "doc.on.clipboard") }
                Button { fullscreen = true } label: {
                    Label("전체화면", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Menu {
                    Button { fontSize = min(fontSize + 1, 28) } label: { Label("크게", systemImage: "plus") }
                    Button { fontSize = max(fontSize - 1, 8) } label: { Label("작게", systemImage: "minus") }
                } label: { Label("글자 크기 (\(Int(fontSize)))", systemImage: "textformat.size") }
                Divider()
                if !keys.keys.isEmpty, session.state == .connected {
                    Button { installKeyPicker = true } label: {
                        Label("내 공개키를 이 서버에 등록", systemImage: "key.horizontal")
                    }
                }
                if case .closed = session.state {
                    Button { session.connect() } label: { Label("재연결", systemImage: "arrow.clockwise") }
                } else {
                    Button { session.disconnect() } label: { Label("연결 끊기", systemImage: "bolt.slash") }
                }
                Button(role: .destructive) {
                    sessions.close(session)
                } label: { Label("세션 닫기", systemImage: "xmark") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(SwiftUI.Color.white.opacity(0.06), in: Circle())
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SwiftUI.Color.panel)
        .overlay(alignment: .bottom) { SwiftUI.Color.hairline.frame(height: 0.5) }
    }

    // MARK: - Floating (키보드 내려간 상태)

    private var floatingControls: some View {
        HStack(spacing: 10) {
            if fullscreen {
                RoundButton(icon: "arrow.down.right.and.arrow.up.left") { fullscreen = false }
            }
            RoundButton(icon: "keyboard", prominent: true) {
                _ = session.terminalView?.becomeFirstResponder()
            }
        }
        .padding(16)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func install(_ key: SSHKeyItem) {
        let pub = key.publicKey.replacingOccurrences(of: "'", with: "")
        let cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && "
            + "(grep -qF '\(pub)' ~/.ssh/authorized_keys || echo '\(pub)' >> ~/.ssh/authorized_keys) && "
            + "chmod 600 ~/.ssh/authorized_keys && echo '✓ Termi: 공개키 등록 완료'\r"
        session.sendText(cmd)
    }
}

private struct SessionTab: View {
    @ObservedObject var session: SSHSession
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(session.host.displayName)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(selected ? SwiftUI.Color.white.opacity(0.12) : SwiftUI.Color.clear, in: Capsule())
            .foregroundStyle(selected ? SwiftUI.Color.white : SwiftUI.Color.textDim)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: SwiftUI.Color {
        switch session.state {
        case .connected: return .accentGreen
        case .connecting, .idle: return .orange
        case .closed: return .red
        }
    }
}

private struct RoundButton: View {
    let icon: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(prominent ? SwiftUI.Color.accent : SwiftUI.Color.panelRaised, in: Circle())
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
    }
}

/// SwiftTerm의 TerminalView를 감싼다. 뷰는 세션이 소유해서 재사용됨.
struct TerminalContainer: UIViewRepresentable {
    let session: SSHSession
    let fontSize: Double
    let theme: TerminalTheme

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let tv: TerminalView
        if let existing = session.terminalView {
            tv = existing
            tv.removeFromSuperview()
        } else {
            tv = TerminalView(frame: .zero)
            tv.terminalDelegate = session
            let bar = KeyBar(terminal: tv)
            bar.onHideKeyboard = { [weak tv] in _ = tv?.resignFirstResponder() }
            tv.inputAccessoryView = bar
            session.terminalView = tv
        }
        apply(tv)
        tv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 6),
            tv.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -6),
            tv.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            tv.bottomAnchor.constraint(equalTo: container.keyboardLayoutGuide.topAnchor),
        ])
        DispatchQueue.main.async {
            _ = tv.becomeFirstResponder()
            if session.state == .idle { session.connect() }
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let tv = session.terminalView { apply(tv) }
    }

    private func apply(_ tv: TerminalView) {
        let c = theme.colors
        let f = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if tv.font.pointSize != f.pointSize { tv.font = f }
        tv.nativeBackgroundColor = UIColor(hex: c.bg)
        tv.nativeForegroundColor = UIColor(hex: c.fg)
        tv.caretColor = UIColor(hex: c.caret)
        tv.backgroundColor = UIColor(hex: c.bg)
        tv.keyboardAppearance = theme.isLight ? .light : .dark
    }
}
