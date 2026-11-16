import SwiftUI
import SwiftTerm

struct TerminalScreen: View {
    @ObservedObject var session: SSHSession
    @EnvironmentObject var sessions: SessionManager
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("theme") private var themeRaw: String = TerminalTheme.midnight.rawValue

    private var theme: TerminalTheme { TerminalTheme(rawValue: themeRaw) ?? .midnight }

    var body: some View {
        VStack(spacing: 0) {
            header
            TerminalContainer(session: session, fontSize: fontSize, theme: theme)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(SwiftUI.Color(hex: theme.colors.bg).ignoresSafeArea())
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

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                sessions.active = nil
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
            }
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.title).font(.subheadline.bold()).lineLimit(1)
                Text(session.host.subtitle).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Button {
                    if let s = UIPasteboard.general.string { session.sendText(s) }
                } label: { Label("붙여넣기", systemImage: "doc.on.clipboard") }
                Button { fontSize = min(fontSize + 1, 28) } label: { Label("글자 크게", systemImage: "plus.magnifyingglass") }
                Button { fontSize = max(fontSize - 1, 8) } label: { Label("글자 작게", systemImage: "minus.magnifyingglass") }
                Divider()
                if case .closed = session.state {
                    Button { session.connect() } label: { Label("재연결", systemImage: "arrow.clockwise") }
                } else {
                    Button { session.disconnect() } label: { Label("연결 끊기", systemImage: "bolt.slash") }
                }
                Button(role: .destructive) {
                    sessions.close(session)
                } label: { Label("세션 닫기", systemImage: "xmark") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SwiftUI.Color.panel)
    }

    private var statusColor: SwiftUI.Color {
        switch session.state {
        case .connected: return .accentGreen
        case .connecting, .idle: return .yellow
        case .closed: return .red
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
            session.terminalView = tv
        }
        apply(tv)
        tv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            tv.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
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
    }
}
