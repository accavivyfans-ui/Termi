import Foundation
import SwiftUI
import UIKit
import CryptoKit
import Citadel
import NIOCore
import NIOSSH
import SwiftTerm

struct HostKeyPrompt: Identifiable {
    let id = UUID()
    let hostID: String
    let keyType: String
    let fingerprint: String
    let changed: Bool
}

enum SSHCredential {
    case password(String)
    case key(SSHKeyItem)
}

struct HostKeyRejected: LocalizedError {
    var errorDescription: String? { "호스트 키를 신뢰하지 않아 연결을 중단했습니다." }
}

/// 서버 호스트 키 확인. 결정은 비동기로(사용자 확인 팝업) 내린다.
final class HostKeyVerifier: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let hostID: String
    let decide: @Sendable (HostKeyPrompt) async -> Bool

    init(hostID: String, decide: @escaping @Sendable (HostKeyPrompt) async -> Bool) {
        self.hostID = hostID
        self.decide = decide
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let openssh = String(openSSHPublicKey: hostKey)
        let parts = openssh.split(separator: " ")
        let type = parts.first.map(String.init) ?? "unknown"
        var fp = "?"
        if parts.count > 1, let blob = Data(base64Encoded: String(parts[1])) {
            let digest = SHA256.hash(data: blob)
            fp = "SHA256:" + Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        }
        let stored = KnownHosts.get(hostID)
        if stored == openssh {
            validationCompletePromise.succeed(())
            return
        }
        let prompt = HostKeyPrompt(hostID: hostID, keyType: type, fingerprint: fp, changed: stored != nil)
        let hostID = self.hostID
        let decide = self.decide
        Task {
            if await decide(prompt) {
                KnownHosts.set(hostID, openssh)
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyRejected())
            }
        }
    }
}

@MainActor
final class SSHSession: NSObject, ObservableObject, Identifiable, TerminalViewDelegate {
    enum State: Equatable {
        case idle, connecting, connected, closed(String?)
    }

    let id = UUID()
    let host: SSHHost
    private let credential: SSHCredential

    @Published var state: State = .idle
    @Published var title: String
    @Published var hostKeyPrompt: HostKeyPrompt?

    /// 세션이 뷰를 소유해서 화면을 나갔다 와도 스크롤백이 유지됨
    var terminalView: TerminalView?
    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var runTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<[UInt8]>.Continuation?
    private var hostKeyContinuation: CheckedContinuation<Bool, Never>?
    private var cols = 80
    private var rows = 24

    var usesKey: Bool { if case .key = credential { return true } else { return false } }

    init(host: SSHHost, credential: SSHCredential) {
        self.host = host
        self.credential = credential
        self.title = host.displayName
    }

    // MARK: - Connection

    func connect() {
        guard state != .connecting && state != .connected else { return }
        runTask?.cancel()
        runTask = Task { await run() }
    }

    func disconnect() {
        inputContinuation?.finish()
        runTask?.cancel()
        let c = client
        Task { try? await c?.close() }
    }

    private func print(_ s: String) {
        terminalView?.feed(text: s)
    }

    private func run() async {
        state = .connecting
        print("\u{1b}[90mConnecting to \(host.subtitle)...\u{1b}[0m\r\n")

        let verifier = HostKeyVerifier(hostID: host.knownHostKey) { [weak self] prompt in
            guard let self else { return false }
            return await self.askHostKey(prompt)
        }

        do {
            let auth: SSHAuthenticationMethod
            switch credential {
            case .password(let pw):
                auth = .passwordBased(username: host.username, password: pw)
            case .key(let item):
                print("\u{1b}[90mUsing key \(item.name) (\(item.typeLabel))\u{1b}[0m\r\n")
                auth = try KeyStore.authMethod(for: item, username: host.username)
            }
            let client = try await SSHClient.connect(
                host: host.hostname,
                port: host.port,
                authenticationMethod: auth,
                hostKeyValidator: .custom(verifier),
                reconnect: .never,
                connectTimeout: .seconds(15)
            )
            self.client = client
            state = .connected
            print("\u{1b}[32mConnected.\u{1b}[0m\r\n")

            let (stream, continuation) = AsyncStream<[UInt8]>.makeStream()
            self.inputContinuation = continuation

            let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: cols,
                terminalRowHeight: rows,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: SSHTerminalModes([:])
            )

            try await client.withPTY(request) { inbound, outbound in
                self.writer = outbound
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await bytes in stream {
                            try await outbound.write(ByteBuffer(bytes: bytes))
                        }
                    }
                    group.addTask {
                        for try await output in inbound {
                            let buffer: ByteBuffer
                            switch output {
                            case .stdout(let b): buffer = b
                            case .stderr(let b): buffer = b
                            }
                            let bytes = Array(buffer.readableBytesView)
                            await MainActor.run {
                                self.terminalView?.feed(byteArray: bytes[...])
                            }
                        }
                    }
                    _ = try await group.next()
                    group.cancelAll()
                }
            }
            finish(nil)
        } catch is CancellationError {
            finish(nil)
        } catch {
            finish(Self.describe(error))
        }
    }

    private func finish(_ error: String?) {
        writer = nil
        inputContinuation?.finish()
        inputContinuation = nil
        let c = client
        client = nil
        Task { try? await c?.close() }
        if let error {
            print("\r\n\u{1b}[31m연결 실패: \(error)\u{1b}[0m\r\n")
        } else {
            print("\r\n\u{1b}[90m[연결 종료]\u{1b}[0m\r\n")
        }
        state = .closed(error)
    }

    static func describe(_ error: Error) -> String {
        let text = String(describing: error)
        let lower = text.lowercased()
        if let k = error as? KeyError { return k.errorDescription ?? text }
        if lower.contains("authentication") || lower.contains("allauthenticationoptionsfailed") {
            return "인증 실패 — 아이디/비밀번호 또는 서버에 등록된 공개키를 확인하세요."
        }
        if lower.contains("timeout") || lower.contains("timedout") {
            return "시간 초과 — 주소/포트/방화벽을 확인하세요."
        }
        if lower.contains("refused") {
            return "연결 거부 — 포트 또는 SSH 서버 상태를 확인하세요."
        }
        if let l = error as? LocalizedError, let d = l.errorDescription { return d }
        return text
    }

    // MARK: - Host key prompt

    private func askHostKey(_ prompt: HostKeyPrompt) async -> Bool {
        await withCheckedContinuation { cont in
            self.hostKeyContinuation = cont
            self.hostKeyPrompt = prompt
        }
    }

    func answerHostKey(_ trust: Bool) {
        hostKeyPrompt = nil
        hostKeyContinuation?.resume(returning: trust)
        hostKeyContinuation = nil
    }

    // MARK: - Input helpers

    func sendText(_ text: String) {
        inputContinuation?.yield(Array(text.utf8))
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if case .closed = state {
            // 연결 종료 후 아무 키(엔터)나 누르면 재접속
            if data.contains(13) { connect() }
            return
        }
        inputContinuation?.yield(Array(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        cols = newCols
        rows = newRows
        if let writer {
            Task { try? await writer.changeSize(cols: newCols, rows: newRows, pixelWidth: 0, pixelHeight: 0) }
        }
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        if !title.isEmpty { self.title = title }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        if let s = String(data: content, encoding: .utf8) { UIPasteboard.general.string = s }
    }
}
